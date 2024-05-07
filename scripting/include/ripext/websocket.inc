typeset WebSocket_ReadCallback
{
    //WebSocket_JSON
    function void (WebSocket ws, JSON message, any data);
    //Websocket_STRING
    function void (WebSocket ws, const char[] buffer, any data);
}

typeset WebSocket_ConnectCallback
{
    function void (WebSocket ws, any data);
}

enum WebSocket_Protocol {
    WebSocket_JSON,
    Websocket_STRING,
}

methodmap WebSocket < Handle {

	// Creates an WebSocket request.
	//
	// The Handle must be freed via delete or CloseHandle().
	//
	// @param url        URL to the Websocket endpoint Such as [scheme]://[hostname]:[port]?[QueryParam1]&[QueryParam2].
    //                   [scheme] Support ws or wss
    //                   [hostname] Support Domain or IP                    
    //                   For example ws://[hostname]:[port]?test1=1&test2=2 Or wss://[hostname]:[port]?test1=1&test2=2
    public native WebSocket(const char[] url);
    public native bool SetHeader(const char[] header, const char[] value);
    public native bool Connect();
    public native bool Close();
    public native bool SetReadCallback(WebSocket_Protocol protocol, WebSocket_ReadCallback callback, any data=0);
    public native bool SetConnectCallback(WebSocket_ConnectCallback callback, any data=0);
    public native bool SetDisconnectCallback(WebSocket_ConnectCallback callback, any data=0);
    public native bool Write(JSON json);
    public native bool WriteString(const char[] content);
    //  Returns whether the tcp stream is open
    public native bool SocketOpen();
    //  Returns the websocket connect status
    public native bool WsOpen();
}