# ClaudeMonitor

macOS menu bar app that shows Claude AI usage and Anthropic service status in real time.

## Install

1. Stáhni `ClaudeMonitor.zip` z [Releases](https://github.com/xerno/ClaudeMonitor/releases)
2. Rozbal a přesuň `ClaudeMonitor.app` do `/Applications`
3. Při prvním spuštění macOS app zablokuje — jdi do **System Settings → Privacy & Security** a klikni **Open Anyway**

## Nastavení

App potřebuje dvě věci z claude.ai:

**Organization ID**
1. Přihlas se na [claude.ai](https://claude.ai)
2. Otevři DevTools (⌘⌥I) → Network → obnov stránku
3. Najdi request na `/api/organizations` → zkopíruj `id` své organizace (formát UUID)

**Session cookie**
1. V DevTools → Application → Cookies → `claude.ai`
2. Zkopíruj hodnotu cookie `sessionKey`

Obojí vlož do ClaudeMonitor při prvním spuštění (nebo přes menu → Preferences).
