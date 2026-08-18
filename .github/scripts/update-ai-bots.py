import urllib.request
import urllib.error
import os
import sys
import tempfile

BOTS_URL = "https://raw.githubusercontent.com/ai-robots-txt/ai.robots.txt/main/robots.txt"
TARGET_FILE = os.environ.get(
    "BOT_LIST_FILE",
    "kubernetes/apps/networking/envoy-gateway/config/resources/block-user-agents.lua",
)
MIN_BOTS_THRESHOLD = 100  # Safety floor to prevent accidental wipeout

LUA_TEMPLATE = """\
function envoy_on_request(request_handle)
  local user_agent = request_handle:headers():get("user-agent") or ""
  local blocked_patterns = {{
{patterns}
  }}

  for _, pattern in ipairs(blocked_patterns) do
    if string.find(user_agent, pattern, 1, true) then
      request_handle:logWarn("blocked bot UA: " .. pattern)
      request_handle:respond({{[":status"] = "200"}}, "")
      return
    end
  end
end
"""


def get_bots():
    try:
        with urllib.request.urlopen(BOTS_URL, timeout=10) as response:
            status = response.getcode()
            if status != 200:
                print(f"Error: Expected HTTP 200, got {status}", file=sys.stderr)
                sys.exit(1)
            content = response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        print(f"Error fetching bots: HTTP {e.code} - {e.reason}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error fetching bots: {e}", file=sys.stderr)
        sys.exit(1)

    bots = []
    for line in content.splitlines():
        line = line.strip()
        if line.lower().startswith("user-agent:"):
            bot = line[len("User-agent:"):].strip()
            if bot and bot != "*":
                bots.append(bot)

    if not bots:
        print("Error: No User-agent entries found in response. Aborting.", file=sys.stderr)
        sys.exit(1)

    return sorted(list(set(bots)))


def validate_lua(content: str) -> None:
    """Basic structural sanity check on generated Lua."""
    if content.count("{") != content.count("}"):
        print("Error: Unbalanced braces in generated Lua.", file=sys.stderr)
        sys.exit(1)
    if content.count('"') % 2 != 0:
        print("Error: Unbalanced double quotes in generated Lua.", file=sys.stderr)
        sys.exit(1)
    if "function envoy_on_request" not in content:
        print("Error: Missing function definition in generated Lua.", file=sys.stderr)
        sys.exit(1)


def main():
    bots = get_bots()

    # Safety Check: Ensure we didn't fetch an empty/broken list
    if len(bots) < MIN_BOTS_THRESHOLD:
        print(
            f"Error: Only {len(bots)} bots identified. This is below the threshold of {MIN_BOTS_THRESHOLD}. "
            "Aborting update to prevent potential wipeout.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Escape backslashes first, then double quotes for Lua strings
    escaped_bots = [b.replace("\\", "\\\\").replace('"', '\\"') for b in bots]
    patterns = ",\n".join(f'    "{b}"' for b in escaped_bots)
    content = LUA_TEMPLATE.format(patterns=patterns)

    validate_lua(content)

    old_content = ""
    if os.path.exists(TARGET_FILE):
        with open(TARGET_FILE, "r", encoding="utf-8") as f:
            old_content = f.read()

    if old_content != content:
        # Diff output for PR body
        old_bots = set()
        if old_content:
            for line in old_content.splitlines():
                stripped = line.strip()
                if stripped.startswith('"') and stripped.rstrip(",").endswith('"'):
                    old_bots.add(stripped.rstrip(",").strip('"').replace('\\"', '"').replace("\\\\", "\\"))

        new_bots = set(bots)
        added = sorted(new_bots - old_bots)
        removed = sorted(old_bots - new_bots)

        diff_lines = []
        if added:
            diff_lines.append("Added:")
            diff_lines.extend(f"  + {b}" for b in added)
        if removed:
            diff_lines.append("Removed:")
            diff_lines.extend(f"  - {b}" for b in removed)
        if not diff_lines:
            diff_lines.append(f"Reformatted ({len(bots)} bots, no content changes)")

        print("\n".join(diff_lines))

        os.makedirs(os.path.dirname(TARGET_FILE), exist_ok=True)

        # Atomic write via temp file + replace
        fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(TARGET_FILE))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(content)
            os.replace(temp_path, TARGET_FILE)
        except Exception:
            os.unlink(temp_path)
            raise

        print(f"\nUpdated {TARGET_FILE}: {len(bots)} bots identified.")
        return True

    print("No changes needed.")
    return False


if __name__ == "__main__":
    main()
    sys.exit(0)
