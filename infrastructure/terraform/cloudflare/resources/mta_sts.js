addEventListener("fetch", event => {
    event.respondWith(handleRequest(event.request))
  })

  async function handleRequest(request) {
    const url = new URL(request.url)
    let response = null

    if (url.pathname === '/.well-known/mta-sts.txt') {
      response = await POLICY_NAMESPACE.get("policy")
    }

    if (response === null) {
      return new Response("Not found", { status: 404 })
    }

    return new Response(response)
  }
