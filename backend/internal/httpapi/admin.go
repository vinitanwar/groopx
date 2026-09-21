package httpapi

import (
	"crypto/subtle"
	"errors"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

func registerAdminRoutes(router *gin.Engine) {
	admin := router.Group("/admin/api")
	admin.POST("/login", adminLogin)
	secured := admin.Group("")
	secured.Use(requireAdmin())
	secured.GET("/me", adminMe)
	secured.GET("/dashboard", adminDashboard)
	secured.GET("/users", adminUsers)
	secured.PATCH("/users/:id/status", updateAdminUserStatus)
	secured.GET("/groups", adminGroups)
	secured.GET("/conversations", adminConversations)
	secured.GET("/reports", adminReports)
	secured.PATCH("/reports/:id", updateAdminReport)
	secured.GET("/calls", adminCalls)
	secured.GET("/audit-logs", adminAuditLogs)
	secured.GET("/announcements", adminAnnouncements)
	secured.POST("/announcements", createAdminAnnouncement)
	secured.GET("/system", adminSystemStatus)
}

func adminAnnouncements(c *gin.Context){rows,err:=db.Query(c.Request.Context(),`SELECT id::text,title,body,audience,recipients,created_by,created_at FROM admin_announcements ORDER BY created_at DESC LIMIT 100`);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"announcements could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0);for rows.Next(){var id,title,body,audience,createdBy string;var recipients int;var created time.Time;if rows.Scan(&id,&title,&body,&audience,&recipients,&createdBy,&created)==nil{items=append(items,gin.H{"id":id,"title":title,"body":body,"audience":audience,"recipients":recipients,"created_by":createdBy,"created_at":created})}};c.JSON(http.StatusOK,gin.H{"items":items,"total":len(items)})}

func createAdminAnnouncement(c *gin.Context){var input struct{Title string `json:"title" binding:"required,max=160"`;Body string `json:"body" binding:"required,max=1000"`;Audience string `json:"audience" binding:"required,oneof=all active"`};if c.ShouldBindJSON(&input)!=nil||strings.TrimSpace(input.Title)==""||strings.TrimSpace(input.Body)==""{c.JSON(http.StatusBadRequest,gin.H{"error":"title, message and audience are required"});return};condition:="account_status<>'deleted'";if input.Audience=="active"{condition="account_status='active'"};ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"announcement could not be created"});return};defer tx.Rollback(ctx);command,err:=tx.Exec(ctx,`INSERT INTO notifications(user_id,type,title,body,data) SELECT id,'announcement',$1,$2,'{}'::jsonb FROM users WHERE `+condition,strings.TrimSpace(input.Title),strings.TrimSpace(input.Body));recipients:=0;if err==nil{recipients=int(command.RowsAffected())};var id string;if err==nil{err=tx.QueryRow(ctx,`INSERT INTO admin_announcements(title,body,audience,created_by,recipients) VALUES($1,$2,$3,$4,$5) RETURNING id::text`,strings.TrimSpace(input.Title),strings.TrimSpace(input.Body),input.Audience,c.GetString("admin_email"),recipients).Scan(&id)};if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"announcement could not be saved"});return};go sendAdminPush(strings.TrimSpace(input.Title),strings.TrimSpace(input.Body),input.Audience);adminAudit(c,"announcement.sent","announcement",id,gin.H{"audience":input.Audience,"recipients":recipients});c.JSON(http.StatusCreated,gin.H{"id":id,"recipients":recipients})}

func adminSystemStatus(c *gin.Context){var databaseOK bool;databaseOK=db.Ping(c.Request.Context())==nil;c.JSON(http.StatusOK,gin.H{"database":databaseOK,"firebase":pushClient!=nil,"livekit":liveKitConfigured(),"media_storage":cfg.S3Bucket!=""&&cfg.S3Endpoint!="","twilio":cfg.TwilioAccountSID!=""&&cfg.TwilioVerifySID!="","environment":os.Getenv("APP_ENV")})}

func adminLogin(c *gin.Context) {
	var input struct {
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid email and password are required"})
		return
	}
	if cfg.AdminEmail == "" || cfg.AdminPassword == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "admin access is not configured"})
		return
	}
	emailMatch := subtle.ConstantTimeCompare([]byte(strings.ToLower(strings.TrimSpace(input.Email))), []byte(strings.ToLower(cfg.AdminEmail))) == 1
	passwordMatch := subtle.ConstantTimeCompare([]byte(input.Password), []byte(cfg.AdminPassword)) == 1
	if !emailMatch || !passwordMatch {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid admin credentials"})
		return
	}
	now := time.Now()
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"iss": "groopx-api", "sub": cfg.AdminEmail, "scope": "admin", "iat": now.Unix(), "exp": now.Add(8 * time.Hour).Unix(),
	}).SignedString([]byte(cfg.JWTSecret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "admin session could not be created"})
		return
	}
	adminAudit(c, "admin.login", "admin", cfg.AdminEmail, gin.H{})
	c.JSON(http.StatusOK, gin.H{"access_token": token, "expires_in": 28800, "admin": gin.H{"email": cfg.AdminEmail, "name": "GroopX Administrator"}})
}

func requireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
		token, err := jwt.Parse(raw, func(token *jwt.Token) (any, error) {
			if token.Method.Alg() != jwt.SigningMethodHS256.Alg() { return nil, errors.New("unexpected signing method") }
			return []byte(cfg.JWTSecret), nil
		}, jwt.WithExpirationRequired(), jwt.WithIssuer("groopx-api"))
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid admin session"})
			return
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok || claims["scope"] != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}
		c.Set("admin_email", claims["sub"])
		c.Next()
	}
}

func adminMe(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"email": c.GetString("admin_email"), "name": "GroopX Administrator", "role": "super_admin"})
}

func adminDashboard(c *gin.Context) {
	ctx := c.Request.Context()
	metrics := gin.H{}
	queries := map[string]string{
		"users": `SELECT COUNT(*)::int FROM users WHERE account_status<>'deleted'`,
		"active_users": `SELECT COUNT(*)::int FROM users WHERE account_status='active'`,
		"new_users_today": `SELECT COUNT(*)::int FROM users WHERE created_at>=CURRENT_DATE`,
		"groups": `SELECT COUNT(*)::int FROM conversations WHERE kind IN ('group','community') AND deleted_at IS NULL`,
		"direct_chats": `SELECT COUNT(*)::int FROM conversations WHERE kind='direct' AND deleted_at IS NULL`,
		"messages_today": `SELECT COUNT(*)::int FROM messages WHERE created_at>=CURRENT_DATE AND deleted_at IS NULL`,
		"open_reports": `SELECT COUNT(*)::int FROM user_reports WHERE status IN ('open','reviewing')`,
		"calls_today": `SELECT COUNT(*)::int FROM calls WHERE started_at>=CURRENT_DATE`,
	}
	for key, query := range queries {
		var value int
		if err := db.QueryRow(ctx, query).Scan(&value); err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "dashboard metrics unavailable"}); return }
		metrics[key] = value
	}
	rows, err := db.Query(ctx, `SELECT day::date::text,
		COALESCE((SELECT COUNT(*) FROM users WHERE created_at>=day AND created_at<day+INTERVAL '1 day'),0)::int,
		COALESCE((SELECT COUNT(*) FROM messages WHERE created_at>=day AND created_at<day+INTERVAL '1 day' AND deleted_at IS NULL),0)::int
		FROM generate_series(CURRENT_DATE-INTERVAL '6 days',CURRENT_DATE,INTERVAL '1 day') day ORDER BY day`)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "dashboard trends unavailable"}); return }
	defer rows.Close()
	trend := make([]gin.H, 0, 7)
	for rows.Next() { var day string; var users, messages int; if rows.Scan(&day, &users, &messages) == nil { trend = append(trend, gin.H{"day": day, "users": users, "messages": messages}) } }
	c.JSON(http.StatusOK, gin.H{"metrics": metrics, "trend": trend})
}

func adminUsers(c *gin.Context) {
	page, limit, offset := pagination(c)
	query := strings.TrimSpace(c.Query("q"))
	status := strings.TrimSpace(c.Query("status"))
	rows, err := db.Query(c.Request.Context(), `SELECT id::text,phone,COALESCE(full_name,''),COALESCE(username,''),COALESCE(avatar_url,''),account_status,created_at,last_seen_at,
		(SELECT COUNT(*)::int FROM conversation_members WHERE user_id=users.id),
		COUNT(*) OVER()::int
		FROM users WHERE ($1='' OR full_name ILIKE '%'||$1||'%' OR username ILIKE '%'||$1||'%' OR phone ILIKE '%'||$1||'%')
		AND ($2='' OR account_status=$2) ORDER BY created_at DESC LIMIT $3 OFFSET $4`, query, status, limit, offset)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "users could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0); total := 0
	for rows.Next() {
		var id, phone, name, username, avatar, accountStatus string; var created time.Time; var lastSeen *time.Time; var chats int
		if rows.Scan(&id, &phone, &name, &username, &avatar, &accountStatus, &created, &lastSeen, &chats, &total) == nil {
			items = append(items, gin.H{"id": id, "phone": phone, "full_name": name, "username": username, "avatar_url": avatar, "status": accountStatus, "created_at": created, "last_seen_at": lastSeen, "conversations": chats})
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "page": page, "limit": limit, "total": total})
}

func updateAdminUserStatus(c *gin.Context) {
	var input struct { Status string `json:"status" binding:"required,oneof=active suspended deleted"`; Reason string `json:"reason" binding:"max=240"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "valid status is required"}); return }
	command, err := db.Exec(c.Request.Context(), `UPDATE users SET account_status=$2,suspended_at=CASE WHEN $2='suspended' THEN NOW() ELSE NULL END,
		suspension_reason=CASE WHEN $2='suspended' THEN NULLIF($3,'') ELSE NULL END,updated_at=NOW() WHERE id=$1`, c.Param("id"), input.Status, strings.TrimSpace(input.Reason))
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error": "user not found"}); return }
	if input.Status != "active" { _, _ = db.Exec(c.Request.Context(), `UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL`, c.Param("id")) }
	adminAudit(c, "user.status_changed", "user", c.Param("id"), gin.H{"status": input.Status, "reason": input.Reason})
	c.JSON(http.StatusOK, gin.H{"id": c.Param("id"), "status": input.Status})
}

func adminGroups(c *gin.Context) {
	page, limit, offset := pagination(c); query := strings.TrimSpace(c.Query("q"))
	rows, err := db.Query(c.Request.Context(), `SELECT c.id::text,COALESCE(c.title,'Untitled group'),COALESCE(c.description,''),COALESCE(c.privacy::text,'private'),c.kind::text,c.created_at,
		COUNT(DISTINCT cm.user_id)::int,COUNT(DISTINCT m.id)::int,COUNT(*) OVER()::int
		FROM conversations c LEFT JOIN conversation_members cm ON cm.conversation_id=c.id LEFT JOIN messages m ON m.conversation_id=c.id AND m.deleted_at IS NULL
		WHERE c.kind IN ('group','community') AND c.deleted_at IS NULL AND ($1='' OR c.title ILIKE '%'||$1||'%')
		GROUP BY c.id ORDER BY c.created_at DESC LIMIT $2 OFFSET $3`, query, limit, offset)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "groups could not be loaded"}); return }
	defer rows.Close(); items := make([]gin.H, 0); total := 0
	for rows.Next() { var id,title,description,privacy,kind string; var created time.Time; var members,messages int; if rows.Scan(&id,&title,&description,&privacy,&kind,&created,&members,&messages,&total)==nil { items=append(items,gin.H{"id":id,"title":title,"description":description,"privacy":privacy,"kind":kind,"created_at":created,"members":members,"messages":messages}) } }
	c.JSON(http.StatusOK,gin.H{"items":items,"page":page,"limit":limit,"total":total})
}

func adminConversations(c *gin.Context) {
	page, limit, offset := pagination(c); kind := strings.TrimSpace(c.Query("kind"))
	rows, err := db.Query(c.Request.Context(), `SELECT c.id::text,c.kind::text,COALESCE(c.title,''),c.created_at,c.last_message_at,
		COUNT(DISTINCT cm.user_id)::int,COUNT(DISTINCT m.id)::int,COUNT(*) OVER()::int
		FROM conversations c LEFT JOIN conversation_members cm ON cm.conversation_id=c.id LEFT JOIN messages m ON m.conversation_id=c.id AND m.deleted_at IS NULL
		WHERE c.deleted_at IS NULL AND ($1='' OR c.kind::text=$1) GROUP BY c.id ORDER BY COALESCE(c.last_message_at,c.created_at) DESC LIMIT $2 OFFSET $3`, kind, limit, offset)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "conversations could not be loaded"}); return }
	defer rows.Close(); items:=make([]gin.H,0); total:=0
	for rows.Next(){var id,itemKind,title string;var created time.Time;var lastMessage *time.Time;var members,messages int;if rows.Scan(&id,&itemKind,&title,&created,&lastMessage,&members,&messages,&total)==nil{items=append(items,gin.H{"id":id,"kind":itemKind,"title":title,"created_at":created,"last_message_at":lastMessage,"members":members,"messages":messages})}}
	c.JSON(http.StatusOK,gin.H{"items":items,"page":page,"limit":limit,"total":total,"privacy_note":"Message contents are not exposed in the admin dashboard."})
}

func adminReports(c *gin.Context) {
	page,limit,offset:=pagination(c); status:=strings.TrimSpace(c.Query("status"))
	rows,err:=db.Query(c.Request.Context(),`SELECT r.id::text,r.reason,COALESCE(r.details,''),r.status,r.created_at,
		COALESCE(reporter.full_name,reporter.username,reporter.phone),COALESCE(reported.full_name,reported.username,reported.phone),r.reported_user_id::text,COUNT(*) OVER()::int
		FROM user_reports r JOIN users reporter ON reporter.id=r.reporter_id JOIN users reported ON reported.id=r.reported_user_id
		WHERE ($1='' OR r.status=$1) ORDER BY r.created_at DESC LIMIT $2 OFFSET $3`,status,limit,offset)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"reports could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0);total:=0
	for rows.Next(){var id,reason,details,itemStatus,reporter,reported,reportedID string;var created time.Time;if rows.Scan(&id,&reason,&details,&itemStatus,&created,&reporter,&reported,&reportedID,&total)==nil{items=append(items,gin.H{"id":id,"reason":reason,"details":details,"status":itemStatus,"created_at":created,"reporter":reporter,"reported_user":reported,"reported_user_id":reportedID})}}
	c.JSON(http.StatusOK,gin.H{"items":items,"page":page,"limit":limit,"total":total})
}

func updateAdminReport(c *gin.Context) {
	var input struct { Status string `json:"status" binding:"required,oneof=open reviewing resolved dismissed"` }
	if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"valid report status is required"});return}
	command,err:=db.Exec(c.Request.Context(),`UPDATE user_reports SET status=$2 WHERE id=$1`,c.Param("id"),input.Status)
	if err!=nil||command.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"report not found"});return}
	adminAudit(c,"report.status_changed","report",c.Param("id"),gin.H{"status":input.Status})
	c.JSON(http.StatusOK,gin.H{"id":c.Param("id"),"status":input.Status})
}

func adminCalls(c *gin.Context) {
	page,limit,offset:=pagination(c); status:=strings.TrimSpace(c.Query("status"))
	rows,err:=db.Query(c.Request.Context(),`SELECT calls.id::text,calls.kind::text,calls.status::text,calls.started_at,calls.answered_at,calls.ended_at,
		COALESCE(users.full_name,users.username,users.phone,'Unknown'),COUNT(call_participants.user_id)::int,COUNT(*) OVER()::int
		FROM calls LEFT JOIN users ON users.id=calls.initiated_by LEFT JOIN call_participants ON call_participants.call_id=calls.id
		WHERE ($1='' OR calls.status::text=$1) GROUP BY calls.id,users.id ORDER BY calls.started_at DESC LIMIT $2 OFFSET $3`,status,limit,offset)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"calls could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0);total:=0
	for rows.Next(){var id,kind,itemStatus,initiator string;var started time.Time;var answered,ended *time.Time;var participants int;if rows.Scan(&id,&kind,&itemStatus,&started,&answered,&ended,&initiator,&participants,&total)==nil{items=append(items,gin.H{"id":id,"kind":kind,"status":itemStatus,"started_at":started,"answered_at":answered,"ended_at":ended,"initiator":initiator,"participants":participants})}}
	c.JSON(http.StatusOK,gin.H{"items":items,"page":page,"limit":limit,"total":total})
}

func adminAuditLogs(c *gin.Context) {
	page,limit,offset:=pagination(c)
	rows,err:=db.Query(c.Request.Context(),`SELECT id::text,admin_email,action,COALESCE(target_type,''),COALESCE(target_id,''),details,created_at,COUNT(*) OVER()::int FROM admin_audit_logs ORDER BY created_at DESC LIMIT $1 OFFSET $2`,limit,offset)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"audit logs could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0);total:=0
	for rows.Next(){var id,email,action,targetType,targetID string;var details map[string]any;var created time.Time;if rows.Scan(&id,&email,&action,&targetType,&targetID,&details,&created,&total)==nil{items=append(items,gin.H{"id":id,"admin_email":email,"action":action,"target_type":targetType,"target_id":targetID,"details":details,"created_at":created})}}
	c.JSON(http.StatusOK,gin.H{"items":items,"page":page,"limit":limit,"total":total})
}

func pagination(c *gin.Context) (int,int,int) {
	page,_:=strconv.Atoi(c.DefaultQuery("page","1"));if page<1{page=1}
	limit,_:=strconv.Atoi(c.DefaultQuery("limit","20"));if limit<1{limit=20};if limit>100{limit=100}
	return page,limit,(page-1)*limit
}

func adminAudit(c *gin.Context, action,targetType,targetID string,details any) {
	email:=c.GetString("admin_email");if email==""{email=cfg.AdminEmail}
	_,_ = db.Exec(c.Request.Context(),`INSERT INTO admin_audit_logs(admin_email,action,target_type,target_id,details) VALUES($1,$2,$3,$4,$5)`,email,action,targetType,targetID,details)
}

func ensureActiveUser(c *gin.Context, userID string) bool {
	var status string
	err:=db.QueryRow(c.Request.Context(),`SELECT account_status FROM users WHERE id=$1`,userID).Scan(&status)
	return err==nil&&status=="active"
}
