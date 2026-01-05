addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url)

  if (url.pathname === '/.well-known/mta-sts.txt') {
    const policy = await POLICY_NAMESPACE.get("policy")
    if (policy !== null) {
      return new Response(policy, {
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'public, max-age=86400'
        }
      })
    }
  }

  return new Response("Not found", { status: 404 })
}
