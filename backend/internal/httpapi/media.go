package httpapi

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var unsafeFileName = regexp.MustCompile(`[^a-zA-Z0-9._-]+`)

func presignMedia(c *gin.Context) {
	var input struct {
		FileName string `json:"file_name" binding:"required,max=180"`
		ContentType string `json:"content_type" binding:"required,max=120"`
		Size int64 `json:"size" binding:"required,gt=0,lte=209715200"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid media metadata"}); return }
	if cfg.S3Endpoint=="" || cfg.S3Bucket=="" || cfg.S3AccessKey=="" || cfg.S3SecretKey=="" || cfg.S3PublicBaseURL=="" {
		c.JSON(http.StatusServiceUnavailable,gin.H{"error":"media storage is not configured"}); return
	}
	random:=make([]byte,16); if _,err:=rand.Read(random);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"upload could not be prepared"});return}
	name:=unsafeFileName.ReplaceAllString(path.Base(input.FileName),"_")
	objectKey:="uploads/"+c.GetString("user_id")+"/"+hex.EncodeToString(random)+"-"+name
	uploadURL,err:=presignedPutURL(objectKey,15*time.Minute);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"upload could not be signed"});return}
	c.JSON(http.StatusOK,gin.H{"object_key":objectKey,"upload_url":uploadURL,"expires_in":900})
}

func completeMediaMessage(c *gin.Context) {
	userID:=c.GetString("user_id")
	var input struct {
		ConversationID string `json:"conversation_id" binding:"required,uuid"`
		ObjectKey string `json:"object_key" binding:"required,max=500"`
		FileName string `json:"file_name" binding:"required,max=180"`
		ContentType string `json:"content_type" binding:"required,max=120"`
		Size int64 `json:"size" binding:"required,gt=0,lte=209715200"`
		DurationMS int `json:"duration_ms" binding:"omitempty,gte=0"`
	}
	if c.ShouldBindJSON(&input)!=nil || !strings.HasPrefix(input.ObjectKey,"uploads/"+userID+"/") { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid uploaded media"});return }
	if !isConversationMember(c,input.ConversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	var otherID string
	if db.QueryRow(c.Request.Context(),`SELECT cm.user_id::text FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id<>$2 WHERE c.id=$1 AND c.kind='direct' LIMIT 1`,input.ConversationID,userID).Scan(&otherID)==nil && usersBlocked(userID,otherID){c.JSON(http.StatusForbidden,gin.H{"error":"media unavailable because communication is blocked"});return}
	kind:="file";if strings.HasPrefix(input.ContentType,"image/"){kind="image"}else if strings.HasPrefix(input.ContentType,"video/"){kind="video"}else if strings.HasPrefix(input.ContentType,"audio/"){kind="audio"}
	publicURL:=strings.TrimRight(cfg.S3PublicBaseURL,"/")+"/"+escapeObjectKey(input.ObjectKey)
	metadata:=gin.H{"file_name":input.FileName,"content_type":input.ContentType,"size":input.Size,"object_key":input.ObjectKey,"url":publicURL,"duration_ms":input.DurationMS}
	metadataJSON,_:=json.Marshal(metadata)
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"media message could not be saved"});return};defer tx.Rollback(ctx)
	var mediaID string;err=tx.QueryRow(ctx,`INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes,duration_ms) VALUES($1,$2,$3,$4,$5,NULLIF($6,0)) RETURNING id::text`,userID,input.ObjectKey,input.FileName,input.ContentType,input.Size,input.DurationMS).Scan(&mediaID)
	if err!=nil{c.JSON(http.StatusConflict,gin.H{"error":"media upload was already completed"});return}
	status:="sent";if onlineRecipients(input.ConversationID,userID)>0||isConversationPeerOnline(input.ConversationID,userID){status="delivered"}
	var messageID string;var createdAt time.Time
	err=tx.QueryRow(ctx,`INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status) VALUES($1,$2,$3,$4,$5,$6) RETURNING id::text,created_at`,input.ConversationID,userID,kind,input.FileName,metadataJSON,status).Scan(&messageID,&createdAt)
	if err==nil{_,err=tx.Exec(ctx,`INSERT INTO message_attachments(message_id,media_id) VALUES($1,$2)`,messageID,mediaID)}
	if err==nil{_,err=tx.Exec(ctx,`UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`,input.ConversationID,createdAt)}
	if err==nil{_,err=tx.Exec(ctx,`UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`,input.ConversationID,userID)}
	if err!=nil || tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"media message could not be saved"});return}
	broadcast(input.ConversationID,userID,gin.H{"type":"message","id":messageID,"conversation_id":input.ConversationID,"sender_id":userID,"text":input.FileName,"kind":kind,"attachment":metadata,"status":status,"created_at":createdAt})
	notifyConversation(input.ConversationID,userID,"media","New attachment",input.FileName,map[string]any{"conversation_id":input.ConversationID,"message_id":messageID,"kind":kind})
	c.JSON(http.StatusCreated,gin.H{"id":messageID,"kind":kind,"attachment":metadata,"status":status,"created_at":createdAt,"mine":true,"text":input.FileName})
}

func uploadMediaMessage(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 27*1024*1024)
	conversationID := strings.TrimSpace(c.PostForm("conversation_id"))
	durationMS, _ := strconv.Atoi(strings.TrimSpace(c.PostForm("duration_ms")))
	if durationMS < 0 { durationMS = 0 }
	if durationMS > 300000 { durationMS = 300000 }
	userID := c.GetString("user_id")
	if conversationID == "" || !isConversationMember(c, conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"not a conversation member"}); return
	}
	var otherID string
	if db.QueryRow(c.Request.Context(), `SELECT cm.user_id::text FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id<>$2 WHERE c.id=$1 AND c.kind='direct' LIMIT 1`, conversationID, userID).Scan(&otherID) == nil && usersBlocked(userID, otherID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"media unavailable because communication is blocked"}); return
	}
	fileHeader, err := c.FormFile("file")
	if err != nil || fileHeader.Size <= 0 || fileHeader.Size > 25*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error":"Without external storage, attachment must be smaller than 25 MB"}); return
	}
	file, err := fileHeader.Open()
	if err != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"attachment could not be read"}); return }
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 25*1024*1024+1))
	if err != nil || len(data) == 0 || len(data) > 25*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error":"Without external storage, attachment must be smaller than 25 MB"}); return
	}
	fileName := unsafeFileName.ReplaceAllString(path.Base(fileHeader.Filename), "_")
	if fileName == "" { fileName = "attachment" }
	contentType := strings.TrimSpace(fileHeader.Header.Get("Content-Type"))
	if contentType == "" || contentType == "application/octet-stream" { contentType = http.DetectContentType(data) }
	if len(contentType) > 120 { contentType = "application/octet-stream" }
	kind := "file"
	if strings.HasPrefix(contentType,"image/") { kind="image" } else if strings.HasPrefix(contentType,"video/") { kind="video" } else if strings.HasPrefix(contentType,"audio/") { kind="audio" }

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"media message could not be saved"}); return }
	defer tx.Rollback(ctx)
	random := make([]byte,16)
	if _,err=rand.Read(random);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"media message could not be saved"});return}
	objectKey := "database/"+hex.EncodeToString(random)+"-"+fileName
	var mediaID string
	err = tx.QueryRow(ctx, `INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes,duration_ms) VALUES($1,$2,$3,$4,$5,NULLIF($6,0)) RETURNING id::text`, userID, objectKey, fileName, contentType, len(data), durationMS).Scan(&mediaID)
	if err == nil { _,err=tx.Exec(ctx, `INSERT INTO media_blobs(media_id,file_data) VALUES($1,$2)`, mediaID, data) }
	scheme:=c.GetHeader("X-Forwarded-Proto");if scheme==""{scheme="http";if c.Request.TLS!=nil{scheme="https"}}
	publicURL:=scheme+"://"+c.Request.Host+"/api/v1/media/files/"+mediaID
	metadata:=gin.H{"file_name":fileName,"content_type":contentType,"size":len(data),"object_key":objectKey,"url":publicURL,"duration_ms":durationMS}
	metadataJSON,_:=json.Marshal(metadata)
	status:="sent";if onlineRecipients(conversationID,userID)>0||isConversationPeerOnline(conversationID,userID){status="delivered"}
	var messageID string;var createdAt time.Time
	if err==nil{err=tx.QueryRow(ctx,`INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status) VALUES($1,$2,$3,$4,$5,$6) RETURNING id::text,created_at`,conversationID,userID,kind,fileName,metadataJSON,status).Scan(&messageID,&createdAt)}
	if err==nil{_,err=tx.Exec(ctx,`INSERT INTO message_attachments(message_id,media_id) VALUES($1,$2)`,messageID,mediaID)}
	if err==nil{_,err=tx.Exec(ctx,`UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`,conversationID,createdAt)}
	if err==nil{_,err=tx.Exec(ctx,`UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`,conversationID,userID)}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"media message could not be saved"});return}
	broadcast(conversationID,userID,gin.H{"type":"message","id":messageID,"conversation_id":conversationID,"sender_id":userID,"text":fileName,"kind":kind,"attachment":metadata,"status":status,"created_at":createdAt})
	notifyConversation(conversationID,userID,"media","New attachment",fileName,map[string]any{"conversation_id":conversationID,"message_id":messageID,"kind":kind})
	c.JSON(http.StatusCreated,gin.H{"id":messageID,"kind":kind,"attachment":metadata,"status":status,"created_at":createdAt,"mine":true,"text":fileName})
}

func getStoredMedia(c *gin.Context) {
	var contentType,fileName string;var data []byte;var createdAt time.Time
	err:=db.QueryRow(c.Request.Context(),`SELECT m.content_type,m.file_name,b.file_data,m.created_at FROM media_objects m JOIN media_blobs b ON b.media_id=m.id WHERE m.id=$1`,c.Param("mediaId")).Scan(&contentType,&fileName,&data,&createdAt)
	if err!=nil{c.Status(http.StatusNotFound);return}
	disposition:="attachment";if strings.HasPrefix(contentType,"image/")||strings.HasPrefix(contentType,"video/")||strings.HasPrefix(contentType,"audio/"){disposition="inline"}
	c.Header("Content-Disposition",disposition+`; filename="`+unsafeFileName.ReplaceAllString(fileName,"_")+`"`)
	c.Header("Cache-Control","public, max-age=86400")
	c.Header("Content-Type",contentType)
	http.ServeContent(c.Writer,c.Request,fileName,createdAt,bytes.NewReader(data))
}

func updateAvatar(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		ObjectKey   string `json:"object_key" binding:"required,max=500"`
		FileName    string `json:"file_name" binding:"required,max=180"`
		ContentType string `json:"content_type" binding:"required,max=120"`
		Size        int64  `json:"size" binding:"required,gt=0,lte=10485760"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile photo"})
		return
	}
	allowedImage := input.ContentType == "image/jpeg" || input.ContentType == "image/png" || input.ContentType == "image/webp" || input.ContentType == "image/heic"
	if cfg.S3PublicBaseURL == "" ||
		!strings.HasPrefix(input.ObjectKey, "uploads/"+userID+"/") ||
		!allowedImage {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile photo"})
		return
	}

	publicURL := strings.TrimRight(cfg.S3PublicBaseURL, "/") + "/" + escapeObjectKey(input.ObjectKey)
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "profile photo could not be saved"})
		return
	}
	defer tx.Rollback(ctx)

	var mediaID string
	err = tx.QueryRow(ctx, `INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes)
		VALUES($1,$2,$3,$4,$5) RETURNING id::text`, userID, input.ObjectKey, input.FileName, input.ContentType, input.Size).Scan(&mediaID)
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE users SET avatar_url=$2,updated_at=NOW() WHERE id=$1`, userID, publicURL)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "profile photo could not be saved"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "profile photo updated", "avatar_url": publicURL, "media_id": mediaID})
}

func removeAvatar(c *gin.Context) {
	userID:=c.GetString("user_id")
	tx,err:=db.Begin(c.Request.Context());if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"profile photo could not be removed"});return};defer tx.Rollback(c.Request.Context())
	_,_=tx.Exec(c.Request.Context(),`DELETE FROM user_avatars WHERE user_id=$1`,userID)
	result, err := tx.Exec(c.Request.Context(), `UPDATE users SET avatar_url=NULL,updated_at=NOW() WHERE id=$1`, userID)
	if err != nil || result.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
		return
	}
	if tx.Commit(c.Request.Context())!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"profile photo could not be removed"});return}
	c.Status(http.StatusNoContent)
}

func uploadAvatar(c *gin.Context){
	c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,6*1024*1024)
	fileHeader,err:=c.FormFile("photo");if err!=nil||fileHeader.Size<=0||fileHeader.Size>5*1024*1024{c.JSON(http.StatusBadRequest,gin.H{"error":"profile photo must be smaller than 5 MB"});return}
	file,err:=fileHeader.Open();if err!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"profile photo could not be read"});return};defer file.Close()
	data,err:=io.ReadAll(io.LimitReader(file,5*1024*1024+1));if err!=nil||len(data)==0||len(data)>5*1024*1024{c.JSON(http.StatusBadRequest,gin.H{"error":"profile photo must be smaller than 5 MB"});return}
	contentType:=http.DetectContentType(data);if contentType!="image/jpeg"&&contentType!="image/png"&&contentType!="image/webp"{c.JSON(http.StatusBadRequest,gin.H{"error":"profile photo must be JPG, PNG or WebP"});return}
	userID:=c.GetString("user_id");scheme:=c.GetHeader("X-Forwarded-Proto");if scheme==""{scheme="http";if c.Request.TLS!=nil{scheme="https"}}
	avatarURL:=scheme+"://"+c.Request.Host+"/api/v1/avatars/"+userID+"?v="+strconv.FormatInt(time.Now().Unix(),10)
	tx,err:=db.Begin(c.Request.Context());if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"profile photo could not be saved"});return};defer tx.Rollback(c.Request.Context())
	_,err=tx.Exec(c.Request.Context(),`INSERT INTO user_avatars(user_id,content_type,image_data) VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET content_type=EXCLUDED.content_type,image_data=EXCLUDED.image_data,updated_at=NOW()`,userID,contentType,data)
	if err==nil{_,err=tx.Exec(c.Request.Context(),`UPDATE users SET avatar_url=$2,updated_at=NOW() WHERE id=$1`,userID,avatarURL)}
	if err!=nil||tx.Commit(c.Request.Context())!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"profile photo could not be saved"});return}
	c.JSON(http.StatusOK,gin.H{"message":"profile photo updated","avatar_url":avatarURL})
}

func getAvatar(c *gin.Context){
	var contentType string;var data []byte
	if db.QueryRow(c.Request.Context(),`SELECT content_type,image_data FROM user_avatars WHERE user_id=$1`,c.Param("userId")).Scan(&contentType,&data)!=nil{c.Status(http.StatusNotFound);return}
	c.Header("Cache-Control","public, max-age=86400");c.Data(http.StatusOK,contentType,data)
}

func presignedPutURL(objectKey string, expires time.Duration)(string,error){
	endpoint,err:=url.Parse(cfg.S3Endpoint);if err!=nil{return "",err}
	endpoint.Path=strings.TrimRight(endpoint.Path,"/")+"/"+url.PathEscape(cfg.S3Bucket)+"/"+escapeObjectKey(objectKey)
	now:=time.Now().UTC();date:=now.Format("20060102");amzDate:=now.Format("20060102T150405Z");scope:=date+"/"+cfg.S3Region+"/s3/aws4_request"
	query:=endpoint.Query();query.Set("X-Amz-Algorithm","AWS4-HMAC-SHA256");query.Set("X-Amz-Credential",cfg.S3AccessKey+"/"+scope);query.Set("X-Amz-Date",amzDate);query.Set("X-Amz-Expires",strconv.FormatInt(int64(expires.Seconds()),10));query.Set("X-Amz-SignedHeaders","host");endpoint.RawQuery=query.Encode()
	canonicalRequest:="PUT\n"+endpoint.EscapedPath()+"\n"+endpoint.RawQuery+"\nhost:"+endpoint.Host+"\n\nhost\nUNSIGNED-PAYLOAD"
	hash:=sha256.Sum256([]byte(canonicalRequest));stringToSign:="AWS4-HMAC-SHA256\n"+amzDate+"\n"+scope+"\n"+hex.EncodeToString(hash[:])
	kDate:=hmacSHA256([]byte("AWS4"+cfg.S3SecretKey),date);kRegion:=hmacSHA256(kDate,cfg.S3Region);kService:=hmacSHA256(kRegion,"s3");kSigning:=hmacSHA256(kService,"aws4_request")
	signature:=hex.EncodeToString(hmacSHA256(kSigning,stringToSign));query.Set("X-Amz-Signature",signature);endpoint.RawQuery=query.Encode();return endpoint.String(),nil
}
func hmacSHA256(key []byte,value string)[]byte{mac:=hmac.New(sha256.New,key);_,_=mac.Write([]byte(value));return mac.Sum(nil)}
func escapeObjectKey(key string)string{parts:=strings.Split(key,"/");for i,value:=range parts{parts[i]=url.PathEscape(value)};return strings.Join(parts,"/")}
