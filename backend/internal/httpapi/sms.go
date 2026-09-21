package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var twilioHTTPClient = &http.Client{Timeout: 15 * time.Second}

func twilioConfigured() bool {
	return cfg.TwilioAccountSID != "" && cfg.TwilioAuthToken != "" && cfg.TwilioVerifySID != ""
}

func sendTwilioOTP(phone string) error {
	values := url.Values{"To": {phone}, "Channel": {"sms"}}
	_, err := twilioVerifyRequest("Verifications", values)
	return err
}

func checkTwilioOTP(phone, code string) (bool, error) {
	values := url.Values{"To": {phone}, "Code": {code}}
	response, err := twilioVerifyRequest("VerificationCheck", values)
	if err != nil {
		return false, err
	}
	return response.Status == "approved", nil
}

type twilioVerifyResponse struct {
	Status  string `json:"status"`
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func twilioVerifyRequest(resource string, values url.Values) (twilioVerifyResponse, error) {
	endpoint := fmt.Sprintf("https://verify.twilio.com/v2/Services/%s/%s", url.PathEscape(cfg.TwilioVerifySID), resource)
	request, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(values.Encode()))
	if err != nil {
		return twilioVerifyResponse{}, err
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.SetBasicAuth(cfg.TwilioAccountSID, cfg.TwilioAuthToken)
	response, err := twilioHTTPClient.Do(request)
	if err != nil {
		return twilioVerifyResponse{}, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return twilioVerifyResponse{}, err
	}
	var payload twilioVerifyResponse
	if err := json.Unmarshal(body, &payload); err != nil {
		return payload, errors.New("sms provider returned an invalid response")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		if payload.Message == "" {
			payload.Message = "sms provider rejected the request"
		}
		return payload, fmt.Errorf("twilio verify error %d: %s", payload.Code, payload.Message)
	}
	return payload, nil
}
