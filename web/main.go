package main

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os/exec"
	"strconv"
	"sync"

	"github.com/BurntSushi/toml"
	"github.com/gin-contrib/sessions"
	"github.com/gin-contrib/sessions/cookie"
	"github.com/gin-gonic/gin"
)

type ForwardingRule struct {
	Listen string `toml:"listen" json:"listen"`
	Remote string `toml:"remote" json:"remote"`
}

type Config struct {
	Network struct {
		NoTCP  bool `toml:"no_tcp"`
		UseUDP bool `toml:"use_udp"`
	} `toml:"network"`
	Endpoints []ForwardingRule `toml:"endpoints"`
}

type PanelConfig struct {
	Auth struct {
		Password string `toml:"password"`
	} `toml:"auth"`
	Server struct {
		Port int `toml:"port"`
	} `toml:"server"`
	HTTPS struct {
		Enabled  bool   `toml:"enabled"`
		CertFile string `toml:"cert_file"`
		KeyFile  string `toml:"key_file"`
	} `toml:"https"`
}

var (
	mu          sync.Mutex
	config      Config
	panelConfig PanelConfig
	httpsWarningShown = false
)

func LoadConfig() error {
	data, err := ioutil.ReadFile("/root/.realm/config.toml")
	if err != nil {
		return err
	}

	if _, err := toml.Decode(string(data), &config); err != nil {
		return err
	}

	return nil
}

func LoadPanelConfig() error {
	data, err := ioutil.ReadFile("./config.toml")
	if err != nil {
		return err
	}

	if _, err := toml.Decode(string(data), &panelConfig); err != nil {
		return err
	}

	return nil
}

func SaveConfig() error {
	mu.Lock()
	defer mu.Unlock()

	var buf bytes.Buffer
	encoder := toml.NewEncoder(&buf)

	// 编码 network 部分
	if err := encoder.Encode(map[string]interface{}{"network": config.Network}); err != nil {
		return err
	}

	// 只有在有规则时才添加 endpoints 部分
	if len(config.Endpoints) > 0 {
		buf.WriteString("\n")
		for _, endpoint := range config.Endpoints {
			buf.WriteString("[[endpoints]]\n")
			if err := encoder.Encode(endpoint); err != nil {
				return err
			}
			buf.WriteString("\n")
		}
	}

	// 写入文件
	return ioutil.WriteFile("/root/.realm/config.toml", buf.Bytes(), 0644)
}

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		session := sessions.Default(c)
		user := session.Get("user")
		if user == nil {
			c.Redirect(http.StatusFound, "/login")
			c.Abort()
			return
		}
		c.Next()
	}
}

func HTTPSRedirect() gin.HandlerFunc {
	return func(c *gin.Context) {
		if panelConfig.HTTPS.Enabled && c.Request.TLS == nil {
			target := "https://" + c.Request.Host + c.Request.URL.Path
			if c.Request.URL.RawQuery != "" {
				target += "?" + c.Request.URL.RawQuery
			}
			c.Redirect(http.StatusMovedPermanently, target)
			c.Abort()
			return
		}
		c.Next()
	}
}

func main() {
	if err := LoadConfig(); err != nil {
		log.Fatalf("无法加载 realm 配置: %v", err)
	}

	if err := LoadPanelConfig(); err != nil {
		log.Fatalf("无法加载面板配置: %v", err)
	}

	r := gin.Default()

	store := cookie.NewStore([]byte("secret"))
	r.Use(sessions.Sessions("realm_session", store))
	r.Use(HTTPSRedirect())

	r.Static("/static", "./static")

	r.GET("/login", func(c *gin.Context) {
		session := sessions.Default(c)
		if session.Get("user") != nil {
			c.Redirect(http.StatusFound, "/")
			return
		}
		c.File("./templates/login.html")
	})

	r.POST("/login", func(c *gin.Context) {
		var loginData struct {
			Password string `json:"password"`
		}

		if err := c.ShouldBindJSON(&loginData); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "无效的请求"})
			return
		}

		if loginData.Password == panelConfig.Auth.Password {
			session := sessions.Default(c)
			session.Set("user", true)
			session.Options(sessions.Options{
				MaxAge: 3600 * 2, // 2小时
			})
			if err := session.Save(); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Session保存失败"})
				return
			}
			c.JSON(http.StatusOK, gin.H{"message": "登录成功"})
		} else {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "密码错误"})
		}
	})

	authorized := r.Group("/")
	authorized.Use(AuthRequired())
	{
		authorized.GET("/", func(c *gin.Context) {
			if !panelConfig.HTTPS.Enabled && !httpsWarningShown {
				c.Header("X-HTTPS-Warning", "当前未启用HTTPS，强烈建议启用HTTPS")
				httpsWarningShown = true
			}
			c.File("./templates/index.html")
		})

		authorized.GET("/get_rules", func(c *gin.Context) {
			pageStr := c.Query("page")
			sizeStr := c.Query("size")
			page, err := strconv.Atoi(pageStr)
			if err != nil || page < 1 {
				page = 1
			}
			size, err := strconv.Atoi(sizeStr)
			if err != nil || size < 1 {
				size = 10
			}

			mu.Lock()
			defer mu.Unlock()

			totalCount := len(config.Endpoints)
			start := (page - 1) * size
			end := start + size
			if start >= totalCount {
				start = totalCount
			}
			if end > totalCount {
				end = totalCount
			}
			paginatedRules := config.Endpoints[start:end]

			c.JSON(200, gin.H{
				"rules": paginatedRules,
				"total": totalCount,
			})
		})

		authorized.POST("/add_rule", func(c *gin.Context) {
			var input ForwardingRule

			if err := c.ShouldBindJSON(&input); err != nil {
				c.JSON(400, gin.H{"error": "无效的输入"})
				return
			}

			mu.Lock()
			config.Endpoints = append(config.Endpoints, input)
			mu.Unlock()

			if err := SaveConfig(); err != nil {
				c.JSON(500, gin.H{"error": "保存配置失败"})
				return
			}

			c.JSON(201, input)
		})

		authorized.DELETE("/delete_rule", func(c *gin.Context) {
			listen := c.Query("listen")

			mu.Lock()
			found := false
			for i, rule := range config.Endpoints {
				if rule.Listen == listen {
					config.Endpoints = append(config.Endpoints[:i], config.Endpoints[i+1:]...)
					found = true
					break
				}
			}
			mu.Unlock()

			if err := SaveConfig(); err != nil {
				c.JSON(500, gin.H{"error": "保存转发规则失败"})
				return
			}

			if found {
				c.JSON(200, gin.H{"message": "保存转发规则成功"})
			} else {
				c.JSON(404, gin.H{"error": "未找到转发规则"})
			}
		})

		authorized.POST("/start_service", func(c *gin.Context) {
			cmd := exec.Command("systemctl", "start", "realm")
			if err := cmd.Run(); err != nil {
				c.JSON(500, gin.H{"error": "服务启动失败"})
				return
			}

			c.JSON(200, gin.H{"message": "服务启动成功"})
		})

		authorized.POST("/stop_service", func(c *gin.Context) {
			cmd := exec.Command("systemctl", "stop", "realm")
			if err := cmd.Run(); err != nil {
				c.JSON(500, gin.H{"error": "服务停止失败"})
				return
			}

			c.JSON(200, gin.H{"message": "服务停止成功"})
		})

		authorized.POST("/restart_service", func(c *gin.Context) {
			cmd := exec.Command("systemctl", "restart", "realm")
			if err := cmd.Run(); err != nil {
				c.JSON(500, gin.H{"error": "服务重启失败"})
				return
			}

			c.JSON(200, gin.H{"message": "服务重启成功"})
		})

		authorized.GET("/check_status", func(c *gin.Context) {
			cmd := exec.Command("systemctl", "is-active", "--quiet", "realm")
			err := cmd.Run()

			var status string
			if err != nil {
				if exitError, ok := err.(*exec.ExitError); ok {
					if exitError.ExitCode() == 3 {
						status = "未启用"
					} else {
						status = "未知状态"
					}
				} else {
					status = "检查失败"
				}
			} else {
				status = "启用"
			}

			c.JSON(200, gin.H{"status": status})
		})

		authorized.POST("/logout", func(c *gin.Context) {
			session := sessions.Default(c)
			session.Clear()
			session.Save()
			c.JSON(http.StatusOK, gin.H{"message": "登出成功"})
		})
	}

	port := panelConfig.Server.Port
	if port == 0 {
		port = 8081 // 默认端口
	}

	if panelConfig.HTTPS.Enabled {
		if panelConfig.HTTPS.CertFile == "" || panelConfig.HTTPS.KeyFile == "" {
			log.Println("警告：HTTPS 已启用，但证书或密钥文件路径未指定。将使用 HTTP 继续。")
			log.Printf("服务器正在使用 HTTP 运行，端口：%d\n", port)
			r.Run(fmt.Sprintf(":%d", port))
		} else {
			log.Printf("服务器正在使用 HTTPS 运行，端口：%d\n", port)
			go func() {
				log.Printf("HTTP 服务器正在运行，端口：8082，用于重定向到 HTTPS\n")
				if err := http.ListenAndServe(":8082", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					target := "https://" + r.Host + r.URL.Path
					if r.URL.RawQuery != "" {
						target += "?" + r.URL.RawQuery
					}
					http.Redirect(w, r, target, http.StatusMovedPermanently)
				})); err != nil {
					log.Fatalf("HTTP 服务器错误: %v", err)
				}
			}()
			if err := r.RunTLS(fmt.Sprintf(":%d", port), panelConfig.HTTPS.CertFile, panelConfig.HTTPS.KeyFile); err != nil {
				log.Fatalf("HTTPS 服务器错误: %v", err)
			}
		}
	} else {
		log.Println("警告：未启用 HTTPS，强烈建议启用 HTTPS。")
		log.Printf("服务器正在使用 HTTP 运行，端口：%d\n", port)
		r.Run(fmt.Sprintf(":%d", port))
	}
}

