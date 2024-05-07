methodmap Crypto
{

    public 	native bool MD5(const char[] source, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool MD5File(const char[] file, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool SHA1(const char[] source, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool SHA1File(const char[] file, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool SHA256(const char[] source, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool SHA256File(const char[] file, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool SHA512(const char[] source, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool SHA512File(const char[] file, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool CRC16(const char[] source, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool CRC16File(const char[] file, char[] buffer, int maxlength, bool uppercase = true);

    public 	native bool CRC32(const char[] source, char[] buffer, int maxlength, bool uppercase = true, bool hexdecimal = true);

    public 	native bool CRC32File(const char[] file, char[] buffer, int maxlength, bool uppercase = true, bool hexdecimal = true);

    //  - 1 is returned on success (the string output buffer is sufficient)
    //  otherwise it is the minimum buffer length required
    public 	native int Base64Encode(const char[] source, char[] buffer, int maxlength);

    //  - 1 is returned on success (the string output buffer is sufficient)
    //  otherwise it is the minimum buffer length required
    public 	native int Base64Decode(const char[] source, char[] buffer, int maxlength);
};