import { http } from "@kit.NetworkKit"
import util from '@ohos.util'

const DEFAULT_CONNECT_TIMEOUT = 30000
const DEFAULT_READ_TIMEOUT = 60000

export interface EventSourceEvent {
  data: string;
  type?: string;
}

export interface EventSourceOptions {
  method?: http.RequestMethod
  headers?: Record<string, string>
  body?: string
  connectTimeout?: number
  readTimeout?: number
}

export class EventSource {
  private httpRequest: http.HttpRequest
  private url: string
  private options: EventSourceOptions
  private onMessageCallback: ((event: EventSourceEvent) => void) | null = null
  private onErrorCallback: ((error: Error) => void) | null = null
  private onCompleteCallback: (() => void) | null = null
  private buffer: string = ''
  private isActive: boolean = false
  private lastEventId: string | null = null
  private decoder: util.TextDecoder = new util.TextDecoder()

  constructor(url: string, options: EventSourceOptions = {}) {
    this.url = url
    this.options = options
    this.httpRequest = http.createHttp()
    this.connect()
  }

  private connect(): void {
    this.isActive = true

    let headers: Record<string, string> = {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache'
    }

    if (this.options.headers) {
      let keys = Object.keys(this.options.headers)
      for (let i = 0; i < keys.length; i++) {
        let key = keys[i]
        headers[key] = this.options.headers[key]
      }
    }

    let connectTimeout = this.options.connectTimeout || DEFAULT_CONNECT_TIMEOUT
    let readTimeout = this.options.readTimeout || DEFAULT_READ_TIMEOUT

    let requestOptions: http.HttpRequestOptions = {
      method: this.options.method || http.RequestMethod.GET,
      header: headers,
      connectTimeout: connectTimeout,
      readTimeout: readTimeout
    }

    if (this.options.body) {
      requestOptions.extraData = this.options.body
    }

    this.httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      if (!this.isActive) {
        return
      }
      try {
        let chunk: string = this.decoder.decode(new Uint8Array(data))
        this.processChunk(chunk)
      } catch (e) {
        this.handleError(new Error('Failed to decode chunk'))
      }
    })

    let promise = this.httpRequest.requestInStream(this.url, requestOptions)

    promise.then((_data: number) => {
      if (this.onCompleteCallback) {
        this.onCompleteCallback()
      }
    }).catch((err: Error) => {
      this.handleError(err)
    })
  }

  private processChunk(chunk: string): void {
    this.buffer += chunk

    let eventEndRegex = /\n\n|\r\n\r\n/
    let lastIndex = 0

    while (true) {
      let match = eventEndRegex.exec(this.buffer)
      if (match === null) {
        break
      }
      let eventText = this.buffer.substring(lastIndex, match.index)
      this.parseEvent(eventText)
      lastIndex = match.index + match[0].length
      this.buffer = this.buffer.substring(lastIndex)
      lastIndex = 0
      eventEndRegex.lastIndex = 0
    }
  }

  private parseEvent(eventText: string): void {
    let lines = eventText.split(/\r\n|\n/)
    let eventType = 'message'
    let data = ''
    let eventId: string | null = null

    for (let line of lines) {
      if (line.startsWith(':')) {
        continue
      }

      let colonIndex = line.indexOf(':')
      if (colonIndex === -1) {
        continue
      }

      let field = line.substring(0, colonIndex).trim()
      let value = line.substring(colonIndex + 1)

      if (value.startsWith(' ')) {
        value = value.substring(1)
      }

      switch (field) {
        case 'event':
          eventType = value
          break
        case 'data':
          data += (data.length > 0 ? '\n' : '') + value
          break
        case 'id':
          eventId = value
          this.lastEventId = eventId
          break
        case 'retry':
          break
      }
    }

    if (data.length > 0 && this.onMessageCallback) {
      this.onMessageCallback({
        data: data.trim(),
        type: eventType,
      })
    }
  }

  private handleError(error: Error): void {
    if (this.onErrorCallback) {
      this.onErrorCallback(error)
    }
    this.close()
  }

  set onMessage(callback: (event: EventSourceEvent) => void) {
    this.onMessageCallback = callback
  }

  set onError(callback: (error: Error) => void) {
    this.onErrorCallback = callback
  }

  set onComplete(callback: () => void) {
    this.onCompleteCallback = callback
  }

  close(): void {
    this.isActive = false
    if (this.httpRequest) {
      this.httpRequest.off('dataReceive')
      this.httpRequest.destroy()
    }
  }
}
