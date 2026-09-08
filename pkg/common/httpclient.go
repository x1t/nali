package common

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

const UserAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36"

type HttpClient struct {
	*http.Client
}

var httpClient *HttpClient

func init() {
	httpClient = &HttpClient{http.DefaultClient}
	httpClient.Timeout = time.Second * 300
	httpClient.Transport = &http.Transport{
		TLSHandshakeTimeout:   time.Second * 5,
		IdleConnTimeout:       time.Second * 10,
		ResponseHeaderTimeout: time.Second * 10,
		ExpectContinueTimeout: time.Second * 20,
		Proxy:                 http.ProxyFromEnvironment,
	}
}

func GetHttpClient() *HttpClient {
	c := *httpClient
	return &c
}

func (c *HttpClient) Get(urls ...string) (body []byte, err error) {
	var req *http.Request
	var resp *http.Response
	var lastErr error

	for _, url := range urls {
		req, err = http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			log.Println(err)
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", UserAgent)
		resp, err = c.Do(req)

		if err != nil {
			if resp != nil && resp.Body != nil {
				_ = resp.Body.Close()
			}
			lastErr = err
			continue
		}
		if resp == nil {
			lastErr = fmt.Errorf("GET %s returned no response", url)
			continue
		}
		if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
			_ = resp.Body.Close()
			lastErr = fmt.Errorf("GET %s returned HTTP status %s", url, resp.Status)
			continue
		}

		body, err = io.ReadAll(resp.Body)
		closeErr := resp.Body.Close()
		if err != nil {
			lastErr = err
			continue
		}
		if closeErr != nil {
			lastErr = closeErr
			continue
		}
		return body, nil
	}

	if lastErr == nil {
		lastErr = errors.New("no download URL provided")
	}
	return nil, lastErr
}
