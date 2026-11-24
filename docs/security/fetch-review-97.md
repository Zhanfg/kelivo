# Fetch network boundary review for issue #97

## Scope

`@kelivo/fetch` exposes `kelivo_fetch` through the in-memory MCP server. The
server parses tool arguments and calls `KelivoFetcher`, which uses
`package:http` for GET and POST. [mcp_provider.dart:1761–1781](../../lib/core/providers/mcp_provider.dart#L1761-L1781),
[kelivo_fetch_server.dart:410–425](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L410-L425),
[kelivo_fetch_server.dart:178–198](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L198)

`fetch_url` is a separate search tool. This review covers its device-local
mode, which makes a GET request through `DioHttpClient`. A configured search
provider can instead fetch the page remotely. That provider's network policy
is outside this review. [tool_handler_service.dart:697–699](../../lib/features/home/services/tool_handler_service.dart#L697-L699),
[web_fetch_tool_service.dart:53–79](../../lib/core/services/search/web_fetch_tool_service.dart#L53-L79),
[web_fetch_service.dart:96–115](../../lib/core/services/search/web_fetch_service.dart#L96-L115),
[web_fetch_service.dart:207–218](../../lib/core/services/search/web_fetch_service.dart#L207-L218),
[web_fetch.dart:68–84](../../lib/core/services/search/web_fetch.dart#L68-L84)

## Findings

| Boundary | Result | Evidence and impact |
| --- | --- | --- |
| Initial URL scheme | PASS | Both paths require HTTP(S) after parsing. Local `fetch_url` also requires a host and supplies HTTPS when a scheme is omitted. [`kelivo_fetch_server.dart:54–59`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L54-L59), [`web_fetch_service.dart:193–205`](../../lib/core/services/search/web_fetch_service.dart#L193-L205) |
| Direct loopback, link-local, and private-network destinations | FINDING | Both paths accept a model-supplied URL without classifying its literal address or resolved peer. An attacker who can influence the tool input can cause the user's device to request local-only listeners, link-local services, or services reachable only on the user's private network. Successful response content is returned to the model. [`kelivo_fetch_server.dart:54–59`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L54-L59), [`kelivo_fetch_server.dart:178–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L193), [`kelivo_fetch_server.dart:201–225`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L201-L225), [`web_fetch_service.dart:193–227`](../../lib/core/services/search/web_fetch_service.dart#L193-L227) |
| Redirects from public to restricted destinations | FINDING | The MCP path inherits automatic redirects from `package:http`. The local search path forwards the request's redirect flag and limit to Dio. Both lack destination validation for each hop. An attacker-controlled public server can make a fetch cross into the user's loopback or private network and return the resulting content through the tool. [`kelivo_fetch_server.dart:178–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L193), [`web_fetch_service.dart:207–227`](../../lib/core/services/search/web_fetch_service.dart#L207-L227), [`dio_http_client.dart:227–245`](../../lib/core/services/network/dio_http_client.dart#L227-L245) |
| `Authorization` and `Cookie` on an unrelated-host redirect | PASS | The MCP tool passes caller headers to the transport. Dart 3.12.1 drops `Authorization` and `Cookie` on a hop to an unrelated host. Local `fetch_url` accepts URL and pagination inputs and adds only a user agent as an application-supplied header. [`kelivo_fetch_server.dart:60–67`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L60-L67), [`kelivo_fetch_server.dart:178–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L193), [`web_fetch_tool_service.dart:33–47`](../../lib/core/services/search/web_fetch_tool_service.dart#L33-L47), [`web_fetch_service.dart:213–216`](../../lib/core/services/search/web_fetch_service.dart#L213-L216). SDK evidence in `_http/http_impl.dart:3062–3113`. |
| `Authorization` and `Cookie` on a subdomain redirect | FINDING | The MCP path inherits Dart's same-scheme, same-port subdomain exception. A redirect from a credentialed origin to an attacker-controlled subdomain can disclose the caller's explicit authorization or cookie headers to that different origin. [`kelivo_fetch_server.dart:60–67`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L60-L67), [`kelivo_fetch_server.dart:178–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L193). SDK evidence in `_http/http_impl.dart:3062–3113`. |
| Other caller-supplied credential headers | FINDING | The MCP tool forwards arbitrary header names. Dart's redirect filter covers a fixed set of names, so a redirect target on an unrelated host can receive a caller's custom credential header such as `X-Api-Key`. [`kelivo_fetch_server.dart:60–67`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L60-L67), [`kelivo_fetch_server.dart:178–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L193). SDK evidence in `_http/http_impl.dart:3070–3113`. |
| Redirect method and body replay | PASS | For MCP POST requests, Dart returns 301, 302, 307, and 308 without following them, and follows 303 as GET with an empty body. The tool reports unfollowed redirects as HTTP errors. Local `fetch_url` uses GET without a body. [`kelivo_fetch_server.dart:184–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L184-L193), [`kelivo_fetch_server.dart:211–222`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L211-L222), [`web_fetch_service.dart:213–216`](../../lib/core/services/search/web_fetch_service.dart#L213-L216). SDK evidence in `_http/http.dart:1764–1790` and `_http/http_impl.dart:3094–3117`. |
| Request log redaction for the initial URL and named sensitive headers | PASS | Local `fetch_url` uses the opt-in request logger. Dio redacts URL user info and recognized query credentials before logging the request, and uses header redaction for both directions. Fixtures check user info, a `token` query value, and `Set-Cookie`. The MCP fetch engine uses `package:http` directly and does not write to this logger. [`dio_http_client.dart:194–201`](../../lib/core/services/network/dio_http_client.dart#L194-L201), [`dio_http_client.dart:255–261`](../../lib/core/services/network/dio_http_client.dart#L255-L261), [`log_redactor.dart:84–102`](../../lib/core/services/logging/log_redactor.dart#L84-L102), [`request_logger.dart:114–123`](../../lib/core/services/network/request_logger.dart#L114-L123), [`kelivo_fetch_server.dart:178–198`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L198) |
| Credential-bearing URLs in logged response headers | FINDING | Dio redacts response headers by name. `Location` is emitted without URL redaction. With request logging enabled, a fetched server can return a credential-bearing `Location` in the final response, placing URL user info or a signed link in the local logs even when response-body logging is disabled. [`dio_http_client.dart:255–259`](../../lib/core/services/network/dio_http_client.dart#L255-L259), [`log_redactor.dart:84–102`](../../lib/core/services/logging/log_redactor.dart#L84-L102), [`log_redactor.dart:137–144`](../../lib/core/services/logging/log_redactor.dart#L137-L144), [`request_logger.dart:70–76`](../../lib/core/services/network/request_logger.dart#L70-L76) |
| Credential-bearing URLs in tool output | FINDING | A failed MCP HTTP request includes the full original URL in the model-visible error. A server can make a credential-bearing request fail and cause its URL credentials to enter the tool result. A successful local `fetch_url` also returns the full original URL in its result, exposing URL user info or query credentials to the model context. [`kelivo_fetch_server.dart:194–197`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L194-L197), [`kelivo_fetch_server.dart:224–225`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L224-L225), [`web_fetch_service.dart:222–227`](../../lib/core/services/search/web_fetch_service.dart#L222-L227), [`web_fetch_tool_service.dart:72–79`](../../lib/core/services/search/web_fetch_tool_service.dart#L72-L79), [`web_fetch_tool_service.dart:105–110`](../../lib/core/services/search/web_fetch_tool_service.dart#L105-L110) |
| Local `fetch_url` deadline and cancellation | PASS | The search timeout defaults to 30 seconds. The same setting supplies Dio's connect, send, and receive timeouts and a total deadline around the request. The wrapper cancels the request and closes the client on exit. [`search_service.dart:191–205`](../../lib/core/services/search/search_service.dart#L191-L205), [`dio_http_client.dart:95–100`](../../lib/core/services/network/dio_http_client.dart#L95-L100), [`web_fetch.dart:68–84`](../../lib/core/services/search/web_fetch.dart#L68-L84) |
| MCP caller deadline and underlying HTTP cancellation | FINDING | The app's MCP caller has a configurable timeout, defaulting to 30 seconds. Its timeout releases the caller, but the in-memory send's cancellation is a no-op and the HTTP fetch has no explicit deadline. A server that stalls a response can retain the underlying request and socket after the caller has timed out. [`mcp_provider.dart:379`](../../lib/core/providers/mcp_provider.dart#L379), [`mcp_provider.dart:1761–1781`](../../lib/core/providers/mcp_provider.dart#L1761-L1781), [`client.dart:1058–1083`](../../dependencies/mcp_client/lib/src/client/client.dart#L1058-L1083), [`transport.dart:14–26`](../../dependencies/mcp_client/lib/src/transport/transport.dart#L14-L26), [`kelivo_fetch_server.dart:178–193`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L178-L193), [`kelivo_fetch_server.dart:551–562`](../../lib/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart#L551-L562) |

## Regression tests

The test file asserts the desired protections. Its connection factory records
attempted destinations and permits sockets only to loopback fixtures registered
by each test. The public fixture uses a reserved `.test` host mapped to loopback.
Every restricted destination is intercepted before DNS or TCP. Redirect
credentials are synthetic. The timeout tests use a loopback server that accepts
the request and waits without sending a response. [kelivo_fetch_security_test.dart](../../test/core/services/mcp/kelivo_fetch_security_test.dart)

The direct-address and private-redirect checks, the subdomain and custom-header
checks, the response `Location` log check, and the MCP connection-cancellation
check are expected to fail against the reviewed code. All retain their security
assertions. The unrelated-origin, POST replay, initial URL and header redaction,
and local timeout checks are expected to pass.

## Production changes for separate authorization

Apply a public-destination policy before each connection, including every
redirect hop and the IP actually used for the connection. A redirect handler
should apply an origin check to credential headers, drop caller-supplied
headers by default across origins, and keep the existing POST replay policy.
Redact credentials in URL-bearing response headers and model-visible URLs and
errors. Give the MCP fetch an owned cancellation mechanism and total deadline,
and cancel its HTTP request when the MCP caller times out.
