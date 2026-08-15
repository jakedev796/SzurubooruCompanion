"""
Outbound address guarding for user-supplied URLs.

Hosts are resolved and the resulting IP objects are classified; hostname strings
are never pattern-matched. Resolving first makes alternate encodings (decimal,
octal, hex, IPv6 shorthand, trailing dot) and public DNS names that point at
private space (localtest.me, *.nip.io) collapse into real addresses.
"""

import asyncio
import errno
import ipaddress
import socket
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple, Union

from app.config import get_settings

IPAddress = Union[ipaddress.IPv4Address, ipaddress.IPv6Address]
IPNetwork = Union[ipaddress.IPv4Network, ipaddress.IPv6Network]

DNS_TIMEOUT_SECONDS = 3.0

# Machine-readable outcomes, surfaced to API clients as "error_code".
ERROR_BLOCKED_ADDRESS = "blocked_address"
ERROR_DNS_RESOLUTION_FAILED = "dns_resolution_failed"

# How an admin lifts the private-network restriction (loopback etc. stay blocked).
PRIVATE_NETWORK_HINT = (
    "Private network URLs are disabled; set CCC_ALLOW_PRIVATE_NETWORK_URLS=true to permit "
    "RFC1918/ULA addresses (loopback, link-local and metadata addresses stay blocked)."
)

# Denied regardless of the CCC_ALLOW_PRIVATE_NETWORK_URLS toggle.
_ALWAYS_BLOCKED: Tuple[Tuple[IPNetwork, str], ...] = (
    (ipaddress.ip_network("0.0.0.0/8"), "unspecified address"),
    (ipaddress.ip_network("127.0.0.0/8"), "loopback address"),
    (ipaddress.ip_network("169.254.0.0/16"), "link-local address"),
    (ipaddress.ip_network("192.0.0.0/24"), "IETF protocol assignment"),
    (ipaddress.ip_network("198.18.0.0/15"), "benchmarking address"),
    (ipaddress.ip_network("224.0.0.0/4"), "multicast address"),
    (ipaddress.ip_network("255.255.255.255/32"), "broadcast address"),
    (ipaddress.ip_network("240.0.0.0/4"), "reserved address"),
    # CGNAT, kept out of the toggle so Alibaba's 100.100.100.200 metadata endpoint
    # stays blocked without a second carve-out.
    (ipaddress.ip_network("100.64.0.0/10"), "carrier-grade NAT address"),
    (ipaddress.ip_network("::/128"), "unspecified address"),
    (ipaddress.ip_network("::1/128"), "loopback address"),
    (ipaddress.ip_network("fe80::/10"), "link-local address"),
    (ipaddress.ip_network("ff00::/8"), "multicast address"),
    # EC2 IMDS lives inside the ULA range the toggle would otherwise permit.
    (ipaddress.ip_network("fd00:ec2::254/128"), "cloud metadata address"),
)

# Denied by default, permitted when CCC_ALLOW_PRIVATE_NETWORK_URLS is enabled.
_PRIVATE_BLOCKED: Tuple[Tuple[IPNetwork, str], ...] = (
    (ipaddress.ip_network("10.0.0.0/8"), "private network address"),
    (ipaddress.ip_network("172.16.0.0/12"), "private network address"),
    (ipaddress.ip_network("192.168.0.0/16"), "private network address"),
    (ipaddress.ip_network("fc00::/7"), "unique local address"),
)

_SIX_TO_FOUR = ipaddress.ip_network("2002::/16")
_NAT64 = ipaddress.ip_network("64:ff9b::/96")


class BlockedHostError(OSError):
    """
    Raised when a host cannot be resolved to at least one permitted address.

    Subclasses OSError so aiohttp preserves it as ClientConnectorError.os_error.
    """

    def __init__(self, message: str, error_code: str = ERROR_BLOCKED_ADDRESS) -> None:
        super().__init__(errno.EACCES, message)
        self.message = message
        self.error_code = error_code


@dataclass(frozen=True)
class HostCheck:
    """Outcome of resolving and classifying every address behind a host."""

    allowed: bool
    error_code: Optional[str] = None
    message: Optional[str] = None


def _embedded_ipv4(address: IPAddress) -> Optional[ipaddress.IPv4Address]:
    """Extract the IPv4 address wrapped by v4-mapped, 6to4 or NAT64 forms."""
    if not isinstance(address, ipaddress.IPv6Address):
        return None
    if address.ipv4_mapped is not None:
        return address.ipv4_mapped
    packed = address.packed
    if address in _SIX_TO_FOUR:
        return ipaddress.IPv4Address(packed[2:6])
    if address in _NAT64:
        return ipaddress.IPv4Address(packed[12:16])
    return None


def classify_address(address: IPAddress) -> Optional[str]:
    """Return a human-readable reason the address is denied, or None if permitted."""
    embedded = _embedded_ipv4(address)
    if embedded is not None:
        embedded_reason = classify_address(embedded)
        if embedded_reason is not None:
            return f"{embedded_reason} embedded in an IPv6 address"

    for network, reason in _ALWAYS_BLOCKED:
        if address.version == network.version and address in network:
            return reason

    if get_settings().allow_private_network_urls:
        return None

    for network, reason in _PRIVATE_BLOCKED:
        if address.version == network.version and address in network:
            return reason
    return None


def _toggle_would_permit(address: IPAddress) -> bool:
    """True when enabling the private-network toggle would actually unblock this address."""
    embedded = _embedded_ipv4(address)
    if embedded is not None and _toggle_would_permit(embedded):
        return True

    for network, _ in _ALWAYS_BLOCKED:
        if address.version == network.version and address in network:
            return False

    return any(
        address.version == network.version and address in network
        for network, _ in _PRIVATE_BLOCKED
    )


def any_toggle_would_permit(hosts: Sequence[str]) -> bool:
    """True when the toggle would unblock at least one of these addresses."""
    for host in hosts:
        try:
            address = ipaddress.ip_address(host.split("%")[0])
        except ValueError:
            continue
        if _toggle_would_permit(address):
            return True
    return False


def filter_allowed_hosts(hosts: Sequence[str]) -> Tuple[List[str], List[str]]:
    """
    Split resolved address literals into the permitted ones and block reasons.

    Returns the surviving literals unchanged so callers can match them back onto
    their own resolution results.
    """
    allowed: List[str] = []
    reasons: List[str] = []
    for host in hosts:
        literal = host.split("%")[0]
        try:
            address = ipaddress.ip_address(literal)
        except ValueError:
            reasons.append(f"{host}: not a valid IP address")
            continue
        reason = classify_address(address)
        if reason is None:
            allowed.append(host)
        else:
            reasons.append(f"{literal}: {reason}")
    return allowed, reasons


async def resolve_host(host: str, port: int = 0) -> List[str]:
    """
    Resolve a host to address literals without blocking the event loop.

    Raises BlockedHostError with the DNS error code on failure or timeout.
    """
    loop = asyncio.get_running_loop()
    try:
        infos = await asyncio.wait_for(
            loop.getaddrinfo(host, port or None, type=socket.SOCK_STREAM),
            timeout=DNS_TIMEOUT_SECONDS,
        )
    except asyncio.TimeoutError:
        raise BlockedHostError(
            f"DNS resolution for '{host}' timed out after {DNS_TIMEOUT_SECONDS:g}s.",
            ERROR_DNS_RESOLUTION_FAILED,
        ) from None
    except OSError as exc:
        raise BlockedHostError(
            f"Could not resolve host '{host}': {exc}.",
            ERROR_DNS_RESOLUTION_FAILED,
        ) from exc

    literals = [str(info[4][0]) for info in infos]
    if not literals:
        raise BlockedHostError(
            f"Could not resolve host '{host}': no addresses returned.",
            ERROR_DNS_RESOLUTION_FAILED,
        )
    return literals


async def check_host(host: str, port: int = 0) -> HostCheck:
    """
    Resolve a host and reject it if ANY returned address is denied.

    Rejecting on any address (rather than the first) stops a resolver that mixes a
    public address in with a private one from slipping through.
    """
    if not host:
        return HostCheck(False, ERROR_BLOCKED_ADDRESS, "URL has no host to resolve.")

    try:
        literals = await resolve_host(host, port)
    except BlockedHostError as exc:
        return HostCheck(False, exc.error_code, exc.message)

    _, reasons = filter_allowed_hosts(literals)
    if reasons:
        message = f"URL host '{host}' resolves to a blocked address ({'; '.join(reasons)})."
        # Only point at the toggle when it would actually unblock this address;
        # suggesting it for loopback or metadata addresses just misleads the admin.
        if not get_settings().allow_private_network_urls and any_toggle_would_permit(literals):
            message = f"{message} {PRIVATE_NETWORK_HINT}"
        return HostCheck(False, ERROR_BLOCKED_ADDRESS, message)
    return HostCheck(True)
