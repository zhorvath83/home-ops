/**
 * HomeGallery Plugin - exifDatePriority
 *
 * This plugin provides an alternative date priority strategy for media entries.
 *
 * DEFAULT PRIORITY (HomeGallery built-in):
 *   1. GPSDateTime
 *   2. SubSecDateTimeOriginal
 *   3. DateTimeOriginal
 *   4. CreateDate
 *
 * THIS PLUGIN'S PRIORITY:
 *   1. SubSecDateTimeOriginal
 *   2. DateTimeOriginal
 *   3. CreateDate
 *   (GPSDateTime is excluded)
 *
 * RATIONALE:
 * GPSDateTime can be unreliable in certain scenarios:
 *   - When GPS was disabled during capture, some devices store epoch (1970-01-01)
 *   - When manually adding location in photo management apps (e.g., Apple Photos),
 *     the GPSDateTime may be set to the date when location was added, not when
 *     the photo was taken
 *   - Some devices incorrectly sync GPSDateTime with GPS satellite time
 *
 * DateTimeOriginal represents the actual capture time set by the camera and is
 * generally more reliable for chronological ordering of photos.
 *
 * USAGE:
 *   1. Copy this file to your HomeGallery plugins directory
 *   2. Configure in gallery.config.yml:
 *        pluginManager:
 *          dirs:
 *            - /data/config/plugins
 *   3. Rebuild the database: gallery.js database
 *
 * See: https://github.com/xemle/home-gallery/issues/143
 */

/**
 * Parses an EXIF date value into ISO 8601 format.
 *
 * Handles various EXIF date formats:
 *   - Standard: "2024:02:23 16:09:35"
 *   - Subseconds: "2024:02:23 16:09:35.449423"
 *   - Timezone: "2024:02:23 16:09:35+02:00"
 *   - UTC: "2024:02:23 16:09:35Z"
 *   - Object: { rawValue: "2024:02:23 16:09:35", tzoffsetMinutes: 120 }
 *
 * Parameters:
 *   date (string|object) - EXIF date value
 *
 * Returns:
 *   string|false - ISO 8601 date string, or false if parsing fails
 */
function parseExiftoolDate(date) {
  // Extract raw value if date is an object (exiftool format)
  const value = date?.rawValue ? date.rawValue : date

  // Validate: must be string, at least 10 chars, not starting with zeros (invalid date)
  if (typeof value !== 'string' || value.length < 10 || value.startsWith('0000')) {
    return false
  }

  // Match EXIF date format: YYYY:MM:DD HH:MM:SS[.subsec][timezone]
  // Capture groups: 1=year, 2=month, 3=day, 4=hour, 5=min, 6=sec, 7=subsec, 8=tz
  const match = value.match(
    /(\d{4}).(\d{2}).(\d{2}).(\d{2}).(\d{2}).(\d{2})(\.\d+)?(([-+](\d{2}:\d{2}|\d{4}))|Z)?\s*$/
  )
  if (!match) {
    return false
  }

  // Build ISO 8601 date string: YYYY-MM-DDTHH:MM:SS
  let iso8601 = `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}`

  // Append subseconds if present (e.g., .449423)
  if (match[7]) {
    iso8601 += match[7]
  }

  // Handle timezone
  if (date?.tzoffsetMinutes && !match[8]) {
    // Calculate offset from tzoffsetMinutes property
    const offset = Math.abs(date.tzoffsetMinutes)
    const negative = date.tzoffsetMinutes < 0
    const hour = String(Math.floor(offset / 60)).padStart(2, '0')
    const minute = String(offset % 60).padStart(2, '0')
    iso8601 += (negative ? '-' : '+') + hour + ':' + minute
  } else if (match[8]) {
    // Use timezone from parsed string
    iso8601 += match[8]
  }

  // Convert to ISO string, return false on invalid date
  try {
    return new Date(iso8601).toISOString()
  } catch (e) {
    return false
  }
}

/**
 * Extracts the preferred date from entry's EXIF metadata.
 *
 * Priority order (GPSDateTime excluded):
 *   1. SubSecDateTimeOriginal - Most precise, includes subseconds
 *   2. DateTimeOriginal - Standard capture timestamp
 *   3. CreateDate - File creation date
 *
 * Parameters:
 *   entry (object) - Storage entry with meta.exif data
 *
 * Returns:
 *   string|false - ISO 8601 date string, or false if not found
 */
function getPreferredDate(entry) {
  const exif = entry.meta?.exif
  if (!exif) {
    return false
  }

  // Priority order - GPSDateTime intentionally excluded
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

/**
 * Plugin definition (HomeGallery plugin API v0.8+)
 */
const plugin = {
  name: 'exifDatePriorityPlugin',
  version: '1.0.0',
  requires: [],

  async initialize(manager) {
    const log = manager.createLogger('plugin.exifDatePriority')
    log.info(`Initialize ${this.name} - using DateTimeOriginal over GPSDateTime`)

    // Create mapper logger once (performance: avoid creating per entry)
    const mapperLog = manager.createLogger('plugin.exifDatePriority.mapper')

    await manager.register('database', {
      name: 'exifDatePriorityMapper',

      // Run after baseMapper (default order: 1) to override its date value
      order: 2,

      /**
       * Override media.date if a more reliable date is available.
       * Runs after baseMapper which may have set date from GPSDateTime.
       */
      mapEntry(entry, media, config) {
        const preferredDate = getPreferredDate(entry)

        if (preferredDate && media.date !== preferredDate) {
          mapperLog.debug(
            `Overriding date for ${entry.sha1sum}: ${media.date} -> ${preferredDate}`
          )
          media.date = preferredDate
        }

        return media
      }
    })
  }
}

export default plugin
