package com.example.leopard_cat

import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.LocalDNSTransport
import java.net.InetAddress

class AndroidLocalDnsTransport : LocalDNSTransport {
    override fun raw(): Boolean = false

    override fun exchange(ctx: ExchangeContext, message: ByteArray) {
        error("Raw DNS exchange is unavailable")
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
        try {
            val addresses = InetAddress.getAllByName(domain)
                .mapNotNull { it.hostAddress }
                .joinToString("\n")
            if (addresses.isEmpty()) {
                ctx.errorCode(3)
            } else {
                ctx.success(addresses)
            }
        } catch (_: Exception) {
            ctx.errorCode(3)
        }
    }
}
