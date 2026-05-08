export interface LyricLine {
  timeMs: number
  text: string
}

export class LyricParser {
  static parse(lrcContent: string): LyricLine[] {
    if (!lrcContent || lrcContent.length === 0) {
      return []
    }

    const lines: LyricLine[] = []
    const lineArray = lrcContent.split('\n')

    for (let i = 0; i < lineArray.length; i++) {
      const rawLine = lineArray[i]
      const line = rawLine.trim()
      if (line.length === 0) {
        continue
      }

      const parsed = LyricParser.parseLine(line)
      if (parsed) {
        lines.push(parsed)
      }
    }

    lines.sort((a, b) => a.timeMs - b.timeMs)

    return lines
  }

  private static parseLine(line: string): LyricLine | null {
    const match = line.match(/^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$/)
    if (!match) {
      return null
    }

    const minutes = parseInt(match[1], 10)
    const seconds = parseInt(match[2], 10)
    const millis = parseInt(match[3].length === 2 ? match[3] + '0' : match[3], 10)
    const text = match[4].trim()

    const timeMs = minutes * 60 * 1000 + seconds * 1000 + millis

    return { timeMs: timeMs, text: text }
  }

  static findCurrentIndex(lines: LyricLine[], currentMs: number): number {
    if (lines.length === 0) {
      return -1
    }

    let index = -1
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].timeMs <= currentMs) {
        index = i
      } else {
        break
      }
    }

    return index
  }

  static formatTime(ms: number): string {
    const totalSec = Math.floor(ms / 1000)
    const min = Math.floor(totalSec / 60)
    const sec = totalSec % 60
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
  }
}
