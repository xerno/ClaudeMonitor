# ClaudeMonitor

macOS menu bar app that monitors Claude AI usage limits and Anthropic service status.

| Active outage | High usage | Critical usage |
|:---:|:---:|:---:|
| ![Active outage with 5h usage](docs/demo1.png) | ![High 5h and 7d usage with minor incident](docs/demo2.png) | ![Critical usage across all windows](docs/demo3.png) |
| 5h window, major API outage | 5h + 7d windows, API degraded | All three windows, all systems OK |

## Install

1. Download `ClaudeMonitor.zip` from [Releases](https://github.com/xerno/ClaudeMonitor/releases)
2. Unzip and move `ClaudeMonitor.app` to `/Applications`
3. On first launch macOS will block the app — go to **System Settings → Privacy & Security** and click **Open Anyway**
