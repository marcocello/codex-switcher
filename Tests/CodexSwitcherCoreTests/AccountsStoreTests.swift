import CodexSwitcherCore
import Foundation
import Testing

@Test("Accounts store loads ISO8601 dates with fractional seconds")
func accountsStoreLoadsFractionalSecondDates() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let fileURL = tmpDir.appendingPathComponent("accounts.json")
    let json = """
    {
      "records": [
        {
          "account": {
            "id": "acc-1",
            "name": "Primary",
            "email": "a@example.com",
            "workspace_name": "Personal",
            "plan_type": "pro",
            "auth_mode": "chat_gpt",
            "is_active": false,
            "created_at": "2026-03-07T13:45:17.000Z",
            "last_used_at": "2026-03-07T14:45:17.000Z"
          },
          "credential": {
            "account_id": "acc-1",
            "auth_mode": "chat_gpt",
            "email": "a@example.com",
            "workspace_name": "Personal",
            "plan_type": "pro",
            "access_token": "token",
            "refresh_token": null,
            "id_token": null,
            "external_account_id": null,
            "api_key": null,
            "raw_auth_json": null,
            "refreshed_at": "2026-03-07T13:45:17.000Z"
          }
        }
      ],
      "active_account_id": "acc-1",
      "usage_by_account_id": {
        "acc-1": {
          "account_id": "acc-1",
          "primary_used_percent": 4,
          "primary_resets_at": "2026-03-07T13:45:17.000Z",
          "secondary_used_percent": 11,
          "secondary_resets_at": "2026-03-08T13:45:17.000Z",
          "plan_type": "pro",
          "error": null
        }
      }
    }
    """
    try Data(json.utf8).write(to: fileURL, options: [.atomic])

    let store = JSONAccountsStore(fileURL: fileURL)
    let loaded = try store.load()

    #expect(loaded.records.count == 1)
    #expect(loaded.activeAccountID == "acc-1")
    #expect(loaded.usageByAccountID["acc-1"]?.primaryUsedPercent == 4)
}
