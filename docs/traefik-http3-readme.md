**🔹  UDP Receive Buffer Size**

HTTP/3 instead of using TCP as the transport layer for the session, it uses QUIC, a new Internet transport protocol.

QUIC streams share the same QUIC connection, so no additional handshakes and slow starts are required to create new ones. This is possible because QUIC packets are encapsulated on top of UDP datagrams.

📍 As of quic-go v0.19.x, you might see warnings about the receive buffer size.

Experiments have shown that QUIC transfers on high-bandwidth connections can be limited by the size of the UDP receive buffer. This buffer holds packets that have been received by the kernel, but not yet read by the application (quic-go in this case). Once this buffer fills up, the kernel will drop any new incoming packet.

**📣  It is recommended to increase the maximum buffer size by running:**

`sysctl -w net.core.rmem_max=2500000`

This command would increase the maximum receive buffer size to roughly 2.5 MB.

Source: https://github.com/lucas-clemente/quic-go/wiki/UDP-Receive-Buffer-Size
