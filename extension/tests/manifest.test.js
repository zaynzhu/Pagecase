import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

test("manifest 权限保持最小集合", async () => {
  const manifestUrl = new URL("../manifest.json", import.meta.url)
  const manifest = JSON.parse(await readFile(manifestUrl, "utf8"))

  assert.equal(manifest.manifest_version, 3)
  assert.deepEqual(
    [...manifest.permissions].sort(),
    ["nativeMessaging", "storage", "tabGroups", "tabs"].sort()
  )
  assert.equal("host_permissions" in manifest, false)
  assert.equal("incognito" in manifest, false)
})
