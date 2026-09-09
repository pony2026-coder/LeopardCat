package com.example.leopard_cat

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborEntryIterator
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState

private const val TAG = "LeopardCatTun"

class AndroidPlatformInterface(
    private val vpnService: VpnService,
    private val onTunCreated: (ParcelFileDescriptor) -> Unit,
) : PlatformInterface {
    private val localDnsTransport = AndroidLocalDnsTransport()

    override fun openTun(options: TunOptions): Int {
        Log.i(TAG, "openTun: mtu=${options.mtu} autoRoute=${options.autoRoute}")
        check(VpnService.prepare(vpnService) == null) { "VPN permission is not granted" }

        val builder = vpnService.Builder().setSession("LeopardCat").setMtu(options.mtu)
        val addresses = options.inet4Address
        while (addresses.hasNext()) {
            val address = addresses.next()
            Log.i(TAG, "openTun: inet4 ${address.address()}/${address.prefix()}")
            builder.addAddress(address.address(), address.prefix())
        }
        val addresses6 = options.inet6Address
        while (addresses6.hasNext()) {
            val address = addresses6.next()
            Log.i(TAG, "openTun: inet6 ${address.address()}/${address.prefix()}")
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            val dns = options.dnsServerAddress
            while (dns.hasNext()) {
                val dnsServer = dns.next()
                Log.i(TAG, "openTun: dns server $dnsServer")
                builder.addDnsServer(dnsServer)
            }

            val routes = options.inet4RouteAddress
            if (routes.hasNext()) {
                while (routes.hasNext()) {
                    val route = routes.next()
                    Log.i(TAG, "openTun: inet4 route ${route.address()}/${route.prefix()}")
                    builder.addRoute(route.address(), route.prefix())
                }
            } else {
                Log.i(TAG, "openTun: no inet4 routes, add 0.0.0.0/0")
                builder.addRoute("0.0.0.0", 0)
            }

            val routes6 = options.inet6RouteAddress
            if (routes6.hasNext()) {
                while (routes6.hasNext()) {
                    val route = routes6.next()
                    Log.i(TAG, "openTun: inet6 route ${route.address()}/${route.prefix()}")
                    builder.addRoute(route.address(), route.prefix())
                }
            }
        }

        val descriptor = builder.establish() ?: error("Unable to establish Android VPN")
        Log.i(TAG, "openTun: established fd=${descriptor.fd}")
        onTunCreated(descriptor)
        return descriptor.fd
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        Log.i(TAG, "autoDetectInterfaceControl(fd=$fd)")
        vpnService.protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun useProcFS(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun underNetworkExtension(): Boolean = false
    override fun usePlatformBridge(): Boolean = false
    override fun usePlatformShell(): Boolean = false
    override fun tailscaleHostname(): String = ""

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) = Unit
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) = Unit
    override fun startNeighborMonitor(listener: NeighborUpdateListener) = Unit
    override fun closeNeighborMonitor(listener: NeighborUpdateListener) = Unit
    override fun clearDNSCache() = Unit
    override fun registerMyInterface(name: String) = Unit
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) = Unit
    override fun cancelNotification(identifier: String, typeID: Int) = Unit

    override fun checkPlatformShell() = error("Platform shell is unavailable")
    override fun createBridge(options: BridgeOptions): BridgeSession = error("Platform bridge is unavailable")
    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String, sourcePort: Int, destinationAddress: String, destinationPort: Int): ConnectionOwner = error("Connection owner lookup is unavailable")
    override fun getInterfaces(): NetworkInterfaceIterator = error("Interface enumeration is unavailable")
    override fun localDNSTransport(): LocalDNSTransport = localDnsTransport
    override fun lookupSFTPServer(): String = error("SFTP is unavailable")
    override fun lookupUser(userName: String): PlatformUser = error("Platform users are unavailable")
    override fun openShellSession(user: PlatformUser, command: String, environment: StringIterator, workingDirectory: String, rows: Int, columns: Int): ShellSession = error("Platform shell is unavailable")
    override fun readSystemSSHHostKey(): String = error("SSH is unavailable")
    override fun readWIFIState(): WIFIState? = null
}
