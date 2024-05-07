enum HTTPStatus
{
	HTTPStatus_Invalid = 0,

	// 1xx Informational
	HTTPStatus_Continue = 100,
	HTTPStatus_SwitchingProtocols = 101,

	// 2xx Success
	HTTPStatus_OK = 200,
	HTTPStatus_Created = 201,
	HTTPStatus_Accepted = 202,
	HTTPStatus_NonAuthoritativeInformation = 203,
	HTTPStatus_NoContent = 204,
	HTTPStatus_ResetContent = 205,
	HTTPStatus_PartialContent = 206,

	// 3xx Redirection
	HTTPStatus_MultipleChoices = 300,
	HTTPStatus_MovedPermanently = 301,
	HTTPStatus_Found = 302,
	HTTPStatus_SeeOther = 303,
	HTTPStatus_NotModified = 304,
	HTTPStatus_UseProxy = 305,
	HTTPStatus_TemporaryRedirect = 307,
	HTTPStatus_PermanentRedirect = 308,

	// 4xx Client Error
	HTTPStatus_BadRequest = 400,
	HTTPStatus_Unauthorized = 401,
	HTTPStatus_PaymentRequired = 402,
	HTTPStatus_Forbidden = 403,
	HTTPStatus_NotFound = 404,
	HTTPStatus_MethodNotAllowed = 405,
	HTTPStatus_NotAcceptable = 406,
	HTTPStatus_ProxyAuthenticationRequired = 407,
	HTTPStatus_RequestTimeout = 408,
	HTTPStatus_Conflict = 409,
	HTTPStatus_Gone = 410,
	HTTPStatus_LengthRequired = 411,
	HTTPStatus_PreconditionFailed = 412,
	HTTPStatus_RequestEntityTooLarge = 413,
	HTTPStatus_RequestURITooLong = 414,
	HTTPStatus_UnsupportedMediaType = 415,
	HTTPStatus_RequestedRangeNotSatisfiable = 416,
	HTTPStatus_ExpectationFailed = 417,
	HTTPStatus_MisdirectedRequest = 421,
	HTTPStatus_TooEarly = 425,
	HTTPStatus_UpgradeRequired = 426,
	HTTPStatus_PreconditionRequired = 428,
	HTTPStatus_TooManyRequests = 429,
	HTTPStatus_RequestHeaderFieldsTooLarge = 431,
	HTTPStatus_UnavailableForLegalReasons = 451,

	// 5xx Server Error
	HTTPStatus_InternalServerError = 500,
	HTTPStatus_NotImplemented = 501,
	HTTPStatus_BadGateway = 502,
	HTTPStatus_ServiceUnavailable = 503,
	HTTPStatus_GatewayTimeout = 504,
	HTTPStatus_HTTPVersionNotSupported = 505,
	HTTPStatus_VariantAlsoNegotiates = 506,
	HTTPStatus_NotExtended = 510,
	HTTPStatus_NetworkAuthenticationRequired = 511,
};

typeset HTTPRequestCallback
{
	function void (HTTPResponse response, any value);
	function void (HTTPResponse response, any value, const char[] error);
};

typeset HTTPFileCallback
{
	function void (HTTPStatus status, any value);
	function void (HTTPStatus status, any value, const char[] error);
};

typeset HTTPFileProgressCallback
{
	// dltotal is the total number of bytes libcurl expects to download in this transfer
	// dlnow is the number of bytes downloaded so far
	// ultotal is the total number of bytes libcurl expects to upload in this transfer
	// ulnow is the number of bytes uploaded so far
	function void (bool isUpload, int dltotal, int dlnow, int ultotal, int ulnow);
};

methodmap HTTPRequest < Handle
{
	// Creates an HTTP request.
	//
	// The Handle is automatically freed when the request is performed.
	// Otherwise, the Handle must be freed via delete or CloseHandle().
	//
	// @param url        URL to the REST API endpoint.
	public native HTTPRequest(const char[] url);

	// Appends a parameter to the form data.
	//
	// The parameter name and value are encoded according to RFC 3986.
	//
	// @param name       Parameter name.
    // @param format     Formatting rules.
    // @param ...        Variable number of format parameters.
	public native void AppendFormParam(const char[] name, const char[] format, any ...);

	// Appends a query parameter to the URL.
	//
	// The parameter name and value are encoded according to RFC 3986.
	//
	// @param name       Parameter name.
    // @param format     Formatting rules.
    // @param ...        Variable number of format parameters.
	public native void AppendQueryParam(const char[] name, const char[] format, any ...);

	// Sets the credentials for HTTP Basic authentication.
	//
	// @param username   Username to use.
	// @param password   Password to use.
	public native void SetBasicAuth(const char[] username, const char[] password);

	/**
     * Sets proxy for the request.
     *
     * @param proxy         Hostname or dotted numerical IP address. A numerical IPv6 address must be written within [brackets].
     *                      To specify port number in this string, append :[port] to the end of the host name (default: 1080).
     *                      The proxy string may be prefixed with [scheme]:// to specify which kind of proxy is used.
     *                      http://
     *                      HTTP Proxy. Default when no scheme is specified.
     *                      https://
     *                      HTTPS Proxy.
     *                      socks4://
     *                      SOCKS4 Proxy.
     *                      socks4a://
     *                      SOCKS4a Proxy. Proxy resolves URL hostname.
     *                      socks5://
     *                      SOCKS5 Proxy.
     *                      socks5h://
     *                      SOCKS5 Proxy. Proxy resolves URL hostname.
     */
    public native void SetProxy(const char[] proxy);

	// Sets an HTTP header.
	//
	// @param name       Header name.
    // @param format     Formatting rules.
    // @param ...        Variable number of format parameters.
	public native void SetHeader(const char[] name, const char[] format, any ...);

	// Performs an HTTP GET request.
	//
	// This function closes the request Handle after completing.
	//
	// @param callback   A function to use as a callback when the request has finished.
	// @param value      Optional value to pass to the callback function.
	public native void Get(HTTPRequestCallback callback, any value = 0);

	// Performs an HTTP POST request.
	//
	// This function closes the request Handle after completing.
	//
	// @param data       JSON data to send.
	// @param callback   A function to use as a callback when the request has finished.
	// @param value      Optional value to pass to the callback function.
	public native void Post(JSON data, HTTPRequestCallback callback, any value = 0);

	// Performs an HTTP PUT request.
	//
	// This function closes the request Handle after completing.
	//
	// @param data       JSON data to send.
	// @param callback   A function to use as a callback when the request has finished.
	// @param value      Optional value to pass to the callback function.
	public native void Put(JSON data, HTTPRequestCallback callback, any value = 0);

	// Performs an HTTP PATCH request.
	//
	// This function closes the request Handle after completing.
	//
	// @param data       JSON data to send.
	// @param callback   A function to use as a callback when the request has finished.
	// @param value      Optional value to pass to the callback function.
	public native void Patch(JSON data, HTTPRequestCallback callback, any value = 0);

	// Performs an HTTP DELETE request.
	//
	// This function closes the request Handle after completing.
	//
	// @param callback   A function to use as a callback when the request has finished.
	// @param value      Optional value to pass to the callback function.
	public native void Delete(HTTPRequestCallback callback, any value = 0);

	// Downloads a file.
	//
	// This function closes the request Handle after completing.
	//
	// @param path       File path to write to.
	// @param callback   A function to use as a callback when the download has finished.
	// @param value      Optional value to pass to the callback function.
	public native void DownloadFile(const char[] path, HTTPFileCallback callback, HTTPFileProgressCallback progresscallback, any value = 0);

	// Uploads a file.
	//
	// This function performs an HTTP PUT request. The file contents are sent in the request body.
	// This function closes the request Handle after completing.
	//
	// @param path       File path to read from.
	// @param callback   A function to use as a callback when the upload has finished.
	// @param value      Optional value to pass to the callback function.
	public native void UploadFile(const char[] path, HTTPFileCallback callback, HTTPFileProgressCallback progresscallback, any value = 0);

	// Performs an HTTP POST request with form data.
	//
	// This function closes the request Handle after completing.
	//
	// @param callback   A function to use as a callback when the request has finished.
	// @param value      Optional value to pass to the callback function.
	public native void PostForm(HTTPRequestCallback callback, any value = 0);

	// Connect timeout in seconds. Defaults to 10.
	property int ConnectTimeout {
		public native get();
		public native set(int connectTimeout);
	}

	// Maximum number of redirects to follow. Defaults to 5.
	property int MaxRedirects {
		public native get();
		public native set(int maxRedirects);
	}

	// Maximum download speed in bytes per second. Defaults to unlimited speed.
	property int MaxRecvSpeed {
		public native get();
		public native set(int maxSpeed);
	}

	// Maximum upload speed in bytes per second. Defaults to unlimited speed.
	property int MaxSendSpeed {
		public native get();
		public native set(int maxSpeed);
	}

	// Timeout in seconds. Defaults to 30.
	property int Timeout {
		public native get();
		public native set(int timeout);
	}
}

methodmap HTTPResponse
{
	// Retrieves an HTTP header from the response.
	//
	// @param name       Header name.
	// @param buffer     String buffer to store value.
	// @param maxlength  Maximum length of the string buffer.
	// @return           True on success, false if the header was not found.
	public native bool GetHeader(const char[] name, char[] buffer, int maxlength);
	
	// Retrieves an HTTP response string from the response.
	//
	// @param buffer     String buffer to store value.
	// @param maxlength  Maximum length of the string buffer.
	// @return           True on success, false if the response string was not found.
	public native bool GetResponseStr(char[] buffer, int maxlength);

	// Retrieves the JSON data of the response.
	//
	// @error            Invalid JSON response.
	property JSON Data {
		public native get();
	}

	// Retrieves the HTTP status of the response.
	property HTTPStatus Status {
		public native get();
	}

	// Retrieves the HTTP response length.
	property int ResponseDataLength {
		public native get();
	}
};