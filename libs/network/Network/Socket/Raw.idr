||| Low-Level C Sockets bindings for Idris. Used by higher-level, cleverer things.
||| Type-unsafe parts. Use Network.Socket for a safe variant.
|||
||| Original (C) SimonJF, MIT Licensed, 2014
||| Modified (C) The Idris Community, 2015, 2016
module Network.Socket.Raw

import public Network.Socket.Data

import Network.FFI
import System.FFI

-- ---------------------------------------------------------------- [ Pointers ]

public export
data RecvStructPtr     = RSPtr AnyPtr

public export
data RecvfromStructPtr = RFPtr AnyPtr

public export
data BufPtr = BPtr AnyPtr

public export
data SockaddrPtr = SAPtr AnyPtr

idrisSocketClass : String
idrisSocketClass = "io/github/mmhelloworld/idris2/runtime/IdrisSocket"

-- ---------------------------------------------------------- [ Socket Utilies ]

||| Put a value in a buffer
export
sock_poke : HasIO io => BufPtr -> Int -> Int -> io ()
sock_poke (BPtr ptr) offset val = primIO $ idrnet_poke ptr offset val

||| Take a value from a buffer
export
sock_peek : HasIO io => BufPtr -> Int -> io Int
sock_peek (BPtr ptr) offset = primIO $ idrnet_peek ptr offset

%foreign
    jvm idrisSocketClass "free"
prim_freeSocketPointer : AnyPtr -> PrimIO ()

||| Frees a given pointer
export
sock_free : HasIO io => BufPtr -> io ()
sock_free (BPtr ptr) = primIO $ prim_freeSocketPointer ptr

export
sockaddr_free : HasIO io => SockaddrPtr -> io ()
sockaddr_free (SAPtr ptr) = primIO $ idrnet_free ptr

||| Allocates an amount of memory given by the ByteLength parameter.
|||
||| Used to allocate a mutable pointer to be given to the Recv functions.
export
sock_alloc : HasIO io => ByteLength -> io BufPtr
sock_alloc bl = map BPtr $ primIO $ idrnet_malloc bl

||| Retrieves the port the given socket is bound to
export
getSockPort : HasIO io => Socket -> io Port
getSockPort sock = primIO $ idrnet_sockaddr_port $ descriptor sock

%foreign
    jvm' idrisSocketClass "getSocketAddressFamily" "java/lang/Object" "int"
prim_getSocketFamily : AnyPtr -> PrimIO Int

%foreign
    jvm' idrisSocketClass "getSocketAddressHostName" "java/lang/Object" "java/lang/String"
prim_getSocketAddressHostName : AnyPtr -> PrimIO String

||| Retrieves a socket address from a sockaddr pointer
export
getSockAddr : HasIO io => SockaddrPtr -> io SocketAddress
getSockAddr (SAPtr ptr) = do
  addr_family_int <- primIO $ prim_getSocketFamily ptr

  -- ASSUMPTION: Foreign call returns a valid int
  assert_total (case getSocketFamily addr_family_int of
    Just AF_INET => do
      ipv4_addr <- primIO $ prim_getSocketAddressHostName ptr

      pure $ parseIPv4 ipv4_addr
    Just AF_INET6 => pure IPv6Addr
    Just AF_UNSPEC => pure InvalidAddress)

export
freeRecvStruct : HasIO io => RecvStructPtr -> io ()
freeRecvStruct (RSPtr p) = primIO $ idrnet_free_recv_struct p

||| Utility to extract data.
export
freeRecvfromStruct : HasIO io => RecvfromStructPtr -> io ()
freeRecvfromStruct (RFPtr p) = primIO $ idrnet_free_recvfrom_struct p

||| Sends the data in a given memory location
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to send the message.
||| @ptr  The location containing the data to send.
||| @len  How much of the data to send.
export
sendBuf : HasIO io
       => (sock : Socket)
       -> (ptr  : BufPtr)
       -> (len  : ByteLength)
       -> io (Either SocketError ResultCode)
sendBuf sock (BPtr ptr) len = do
  send_res <- primIO $ idrnet_send_buf (descriptor sock) ptr len

  if send_res == (-1)
   then map Left getErrno
   else pure $ Right send_res

||| Receive data from a given memory location.
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to receive the message.
||| @ptr  The location containing the data to receive.
||| @len  How much of the data to receive.
export
recvBuf : HasIO io
       => (sock : Socket)
       -> (ptr  : BufPtr)
       -> (len  : ByteLength)
       -> io (Either SocketError ResultCode)
recvBuf sock (BPtr ptr) len = do
  recv_res <- primIO $ idrnet_recv_buf (descriptor sock) ptr len

  if (recv_res == (-1))
    then map Left getErrno
    else pure $ Right recv_res

||| Send a message stored in some buffer.
|||
||| Returns on failure a `SocketError`
||| Returns on success the `ResultCode`
|||
||| @sock The socket on which to send the message.
||| @addr Address of the recipient.
||| @port The port on which to send the message.
||| @ptr  A Pointer to the buffer containing the message.
||| @len  The size of the message.
export
sendToBuf : HasIO io
         => (sock : Socket)
         -> (addr : SocketAddress)
         -> (port : Port)
         -> (ptr  : BufPtr)
         -> (len  : ByteLength)
         -> io (Either SocketError ResultCode)
sendToBuf sock addr p (BPtr dat) len = do
  sendto_res <- primIO $ idrnet_sendto_buf
                (descriptor sock) dat len (show addr) p (toCode $ family sock)

  if sendto_res == (-1)
    then map Left getErrno
    else pure $ Right sendto_res

||| Utility function to get the payload of the sent message as a `String`.
export
foreignGetRecvfromPayload : HasIO io => RecvfromStructPtr -> io String
foreignGetRecvfromPayload (RFPtr p) = primIO $ idrnet_get_recvfrom_payload p 

||| Utility function to return senders socket address.
export
foreignGetRecvfromAddr : HasIO io => RecvfromStructPtr -> io SocketAddress
foreignGetRecvfromAddr (RFPtr p) = do
  sockaddr_ptr <- map SAPtr $ primIO $ idrnet_get_recvfrom_sockaddr p
  getSockAddr sockaddr_ptr

||| Utility function to return sender's IPV4 port.
export
foreignGetRecvfromPort : HasIO io => RecvfromStructPtr -> io Port
foreignGetRecvfromPort (RFPtr p) = do
  sockaddr_ptr <- primIO $ idrnet_get_recvfrom_sockaddr p
  port         <- primIO $ idrnet_sockaddr_ipv4_port sockaddr_ptr
  pure port

||| Receive a message placed on a 'known' buffer.
|||
||| Returns on failure a `SocketError`.
||| Returns on success a pair of
||| + `UDPAddrInfo` :: The address of the sender.
||| + `Int`         :: Result value from underlying function.
|||
||| @sock The channel on which to receive.
||| @ptr  Pointer to the buffer to place the message.
||| @len  Size of the expected message.
|||
export
recvFromBuf : HasIO io
           => (sock : Socket)
           -> (ptr  : BufPtr)
           -> (len  : ByteLength)
           -> io (Either SocketError (UDPAddrInfo, ResultCode))
recvFromBuf sock (BPtr ptr) bl = do
  recv_ptr <- primIO $ idrnet_recvfrom_buf (descriptor sock) ptr bl

  let recv_ptr' = RFPtr recv_ptr

  isnull <- nullPtr recv_ptr

  if isnull
    then map Left getErrno
    else do
      result <- primIO $ idrnet_get_recvfrom_res recv_ptr
      if result == -1
        then do
          freeRecvfromStruct recv_ptr'
          map Left getErrno
        else do
          port <- foreignGetRecvfromPort recv_ptr'
          addr <- foreignGetRecvfromAddr recv_ptr'
          freeRecvfromStruct recv_ptr'
          pure $ Right (MkUDPAddrInfo addr port, result + 1)
