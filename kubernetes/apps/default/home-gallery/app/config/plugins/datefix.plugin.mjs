// HomeGallery Plugin - DateFix
// Fixes GPS date priority issue by preferring DateTimeOriginal over GPSDateTime
// See: https://github.com/xemle/home-gallery/issues/143

// Helper function to parse exiftool date (based on home-gallery source date.js)
function parseExiftoolDate(date) {
  const value = date?.rawValue ? date.rawValue : date
  if (typeof value !== 'string' || value.length < 10 || value.startsWith('0000')) {
    return false
  }

  const match = value.match(/(\d{4}).(\d{2}).(\d{2}).(\d{2}).(\d{2}).(\d{2})(\.\d+)?(([-+](\d{2}:\d{2}|\d{4}))|Z)?\s*$/)
  if (!match) {
    return false
  }

  let iso8601 = `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}${match[7] ? match[7] : ''}`
  if (date?.tzoffsetMinutes && !match[8]) {
    const offset = Math.abs(date.tzoffsetMinutes)
    const negative = date.tzoffsetMinutes < 0
    const hour = '' + Math.floor(offset / 60)
    const minute = '' + (offset % 60)
    const offsetText = (negative ? '-' : '+') + hour.padStart(2, '0') + ':' + minute.padStart(2, '0')
    iso8601 += offsetText
  } else if (match[8]) {
    iso8601 += match[8]
  }

  try {
    return new Date(iso8601).toISOString()
  } catch (e) {
    return false
  }
}

function getPreferredDate(entry) {
  const exif = entry.meta?.exif
  if (!exif) {
    return false
  }

  // Priority: SubSecDateTimeOriginal > DateTimeOriginal > CreateDate
  // GPSDateTime is intentionally EXCLUDED to fix the issue
  const dateKeys = ['SubSecDateTimeOriginal', 'DateTimeOriginal', 'CreateDate']

  for (const key of dateKeys) {
    if (exif[key]) {
      const parsed = parseExiftoolDate(exif[key])
      if (parsed) {
        return parsed
      }
    }
  }

  return false
}

const plugin = {
  name: 'datefixPlugin',
  version: '1.0.0',
  requires: [],

  async initialize(manager) {
    const log = manager.createLogger('plugin.datefix')
    log.info(`Initialize ${this.name} - fixes GPS date priority issue`)

    // Create mapper logger once, outside mapEntry for performance
    const mapperLog = manager.createLogger('plugin.datefix.mapper')

    await manager.register('database', {
      name: 'datefixMapper',
      // Run AFTER baseMapper (which has default order 1)
      order: 2,

      mapEntry(entry, media, config) {
        const preferredDate = getPreferredDate(entry)

        if (preferredDate && media.date !== preferredDate) {
          mapperLog.debug(`Fixing date for ${entry.sha1sum}: ${media.date} -> ${preferredDate}`)
          media.date = preferredDate
        }

        return media
      }
    })
  }
}

export default plugin
