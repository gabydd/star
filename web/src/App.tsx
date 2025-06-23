import { createSignal, Show } from "solid-js";
import initStar from "./star.wasm?init";
let wasm: WebAssembly.Instance;
const websocket = new WebSocket("ws:0.0.0.0:1999");
websocket.binaryType = "arraybuffer";
type Star = ReturnType<typeof createWrapper>;
const stars: Star[]= [];
websocket.addEventListener("error", (er) => {
  console.error(er)
})
websocket.addEventListener("message", (ev) => {
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
  const ret = {
    insert(pos: number, text: string) {
      const string = allocString(text)
      wasm.exports.insert(wrapper, pos, string.ptr, string.len);
      string.free();
      ret.snapshot();
    },
    remove(pos: number, count: number) {
      wasm.exports.delete(wrapper, pos, count);
      ret.snapshot();
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
    snapshot() {
      wasm.exports.snapshot(wrapper);
      setText(textDecoder.decode(lastSlice));
      console.log(text());
    },
    destroy() {
      wasm.exports.destroyWrapper(wrapper);
    },
    text,
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
  stars.push(star);
  return <div>
    <textarea oninput={(e) => {
      console.log(e.inputType);
      if (e.inputType === "deleteContentBackward") {
        star.remove(e.target.selectionStart, star.text().length - e.target.value.length)
      } else if (e.inputType === "insertText") {
        star.insert(e.target.selectionStart-1, e.data);
      }
    }}></textarea>
    <p>{star.text()}</p>
  </div>
}

export default function App() {
  return <div>
    Hello world!
    <Show when={!loading()}  fallback={<div>loading...</div>}>
      <Star />
    </Show>
  </div>
};
