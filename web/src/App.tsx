import { createEffect, createSignal, Show } from "solid-js";
import initStar from "./star.wasm?init";
let wasm: WebAssembly.Instance;
const ip = location.hostname
const websocket = new WebSocket(`ws:${ip}:1999`);
websocket.binaryType = "arraybuffer";
type Star = ReturnType<typeof createWrapper>;
const stars: Star[]= [];
websocket.addEventListener("error", (er) => {
  console.error(er)
})

let lastData;
websocket.addEventListener("message", (ev) => {
  lastData = new Uint8Array(ev.data);
  for (const star of stars) {
    star.merge(new Uint8Array(ev.data));
  }
  console.log(ev);
})
const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

function allocString(string) {
  const text = textEncoder.encode(string);
  const ptr = wasm.exports.alloc(text.length);
  new Uint8Array(wasm.exports.memory.buffer).set(text, ptr);
  const ret = {
    ptr,
    len: text.length,
    free: () => { wasm.exports.free(ptr, ret.len); },
  };
  return ret;
}

function createWrapper() {
  const agentId = BigInt(Math.round(Math.random() * 100000));
  const wrapper = wasm.exports.createWrapper(agentId);
  const [text, setText] = createSignal("");
  const [cursor, setCursor] = createSignal(0);
  const ret = {
    insert(pos: number, text: string) {
      const string = allocString(text)
      wasm.exports.insert(wrapper, pos, string.ptr, string.len);
      string.free();
      ret.snapshot();
      websocket.send(ret.toBytes());
    },
    remove(pos: number, count: number) {
      wasm.exports.delete(wrapper, pos, count);
      ret.snapshot();
      websocket.send(ret.toBytes());
    },
    merge(bytes: Uint8Array) {
      const ptr = wasm.exports.alloc(bytes.length);
      new Uint8Array(wasm.exports.memory.buffer).set(bytes, ptr);
      wasm.exports.merge(wrapper, ptr, bytes.length);
      ret.snapshot();
    },
    toBytes() {
      wasm.exports.toBytes(wrapper);
      return lastSlice;
    
    },
    wasmCursor() {
      return wasm.exports.cursor(wrapper);
    },
    setCursor(pos: number) {
      return wasm.exports.setCursor(wrapper, pos);
    },
    snapshot() {
      wasm.exports.snapshot(wrapper);
      setText(textDecoder.decode(lastSlice));
      setCursor(ret.wasmCursor());
    },
    destroy() {
      wasm.exports.destroyWrapper(wrapper);
    },
    text,
    cursor,
  };
  return ret;
}

const [loading, setLoading] = createSignal(true);
initStar({env: {returnSlice}}).then(wasmInstance => {
  wasm = wasmInstance;
  setLoading(false);
});

let lastSlice: Uint8Array;
function returnSlice(ptr, len) {
  const arr = new Uint8Array(wasm.exports.memory.buffer)
  lastSlice = arr.slice(ptr, ptr + len);
}

function Star() {
  const star = createWrapper();
  let textArea!: HTMLTextAreaElement;
  stars.push(star);
  if (lastData) star.merge(lastData)
  createEffect(() => {
    textArea.value = star.text();
    textArea.selectionStart = star.cursor()
    textArea.selectionEnd = star.cursor()
  })
  return <div>
    <textarea rows={50} cols={30} ref={textArea} oninput={(e) => {
      console.log(e.inputType);
      if (e.inputType === "deleteContentBackward") {
        star.remove(e.target.selectionStart, star.text().length - e.target.value.length)
      } else if (e.inputType === "insertText") {
        star.setCursor(e.target.selectionStart - e.data.length);
        star.insert(e.target.selectionStart-e.data.length, e.data);
      } else if (e.inputType === "insertLineBreak") {
        star.setCursor(e.target.selectionStart - 1);
        star.insert(e.target.selectionStart-1, "\n");
      }
    }}
      onselectionchange={(e) => {
        star.setCursor(e.target.selectionStart)
      }}
      ></textarea>
  </div>
}

export default function App() {
  return <div>
    <Show when={!loading()}  fallback={<div>loading...</div>}>
      <Star />
    </Show>
  </div>
};
