addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url)
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  }

  if (request.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    if (url.pathname === '/otp-onyp/dinamikus.json') {
      const responseData = await processOtpOnypDinamikus()
      const jsonResponse = JSON.stringify({ data: responseData }, null, 2)
      return new Response(jsonResponse, {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=43200',  // Cache for 12 hours
          ...corsHeaders
        }
      })
    } else {
      return new Response("Not found", {
        status: 404,
        headers: corsHeaders
      })
    }
  } catch (error) {
    return new Response(`Error: ${error.message}`, {
      status: 500,
      headers: corsHeaders
    })
  }
}

async function processOtpOnypDinamikus() {
  const url = 'https://www.otpnyugdij.hu/api/arfolyam/letoltes?portfolios=Dinamikus&startDate=20091201&endDate=20991231'
  try {
    const response = await fetch(url)
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }
    const text = await response.text()
    const lines = text.split('\n')
    const data = []
    // Skip the first two lines (header information)
    for (let i = 2; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line) {
        const [date, price, ,] = line.split(';')
        if (date && price) {
          const formattedDate = formatDate(date)
          const formattedPrice = formatPrice(price)
          if (formattedDate) {
            data.push({
              price: formattedPrice,
              date: formattedDate
            })
          }
        }
      }
    }
    return data
  } catch (error) {
    console.error('Error fetching or processing data:', error)
    throw error
  }
}

function formatDate(dateString) {
  try {
    // Remove any trailing dots and trim spaces
    const cleanedDate = dateString.trim().replace(/\.$/, '');
    const [year, month, day] = cleanedDate.split('. ');
    if (!year || !month || !day) {
      console.warn(`Invalid date format: ${dateString}`);
      return null;
    }
    // Format date as YYYY-MM-DD
    return `${year.trim()}-${month.padStart(2, '0')}-${day.trim()}`;
  } catch (error) {
    console.warn(`Error formatting date: ${dateString}`, error);
    return null;
  }
}

function formatPrice(priceString) {
  const price = parseFloat(priceString.replace(',', '.'))
  return Number(price.toFixed(6))
}
