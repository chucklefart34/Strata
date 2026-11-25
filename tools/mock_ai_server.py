"""Mock ComfyUI + Anthropic API for testing Strata's AI Studio offline."""
import json, re, sys, threading, time, io, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from PIL import Image, ImageDraw

PROMPTS = {}      # id -> {graph, t, n}
UPLOADS = {}      # name -> bytes
LOG = []
COUNTER = [0]

OBJECT_INFO = {
    "CheckpointLoaderSimple": {"input": {"required": {"ckpt_name": [["illustrious_dark_xl.safetensors", "sd15_ink.safetensors"]]}}},
    "LoraLoader": {"input": {"required": {"model": ["MODEL"], "clip": ["CLIP"], "lora_name": [["noir_ink.safetensors"]],
                                           "strength_model": ["FLOAT", {"default": 1.0}], "strength_clip": ["FLOAT", {"default": 1.0}]}}},
    "ControlNetLoader": {"input": {"required": {"control_net_name": [["sdxl_lineart.safetensors"]]}}},
    "ControlNetApplyAdvanced": {"input": {"required": {"positive": ["CONDITIONING"], "negative": ["CONDITIONING"], "control_net": ["CONTROL_NET"], "image": ["IMAGE"],
        "strength": ["FLOAT", {"default": 1.0}], "start_percent": ["FLOAT", {"default": 0}], "end_percent": ["FLOAT", {"default": 1}]}, "optional": {"vae": ["VAE"]}}},
    "KSampler": {"input": {"required": {"model": ["MODEL"], "seed": ["INT", {"default": 0}], "steps": ["INT", {"default": 20}], "cfg": ["FLOAT", {"default": 8}],
        "sampler_name": [["euler", "dpmpp_2m"]], "scheduler": [["normal", "karras"]], "positive": ["CONDITIONING"], "negative": ["CONDITIONING"],
        "latent_image": ["LATENT"], "denoise": ["FLOAT", {"default": 1.0}]}}},
    "CLIPTextEncode": {"input": {"required": {"text": ["STRING"], "clip": ["CLIP"]}}},
    "EmptyLatentImage": {"input": {"required": {"width": ["INT", {}], "height": ["INT", {}], "batch_size": ["INT", {"default": 1}]}}},
    "VAEEncode": {"input": {"required": {"pixels": ["IMAGE"], "vae": ["VAE"]}}},
    "VAEDecode": {"input": {"required": {"samples": ["LATENT"], "vae": ["VAE"]}}},
    "LoadImage": {"input": {"required": {"image": [["example.png"]]}}},
    "ImageBatch": {"input": {"required": {"image1": ["IMAGE"], "image2": ["IMAGE"]}}},
    "SaveImage": {"input": {"required": {"images": ["IMAGE"], "filename_prefix": ["STRING", {"default": "ComfyUI"}]}}},
    "IPAdapterUnifiedLoader": {"input": {"required": {"model": ["MODEL"], "preset": ["COMBO", {"options": ["LIGHT - SD1.5 only (low strength)", "STANDARD (medium strength)", "PLUS (high strength)"]}]}}},
    "IPAdapterAdvanced": {"input": {"required": {"model": ["MODEL"], "ipadapter": ["IPADAPTER"], "image": ["IMAGE"], "weight": ["FLOAT", {"default": 1.0}],
        "weight_type": [["linear", "ease in"]], "combine_embeds": [["concat", "add"]], "start_at": ["FLOAT", {"default": 0}], "end_at": ["FLOAT", {"default": 1}],
        "embeds_scaling": [["V only", "K+V"]]}, "optional": {"image_negative": ["IMAGE"]}}},
}


def render(graph):
    COUNTER[0] += 1
    n = COUNTER[0]
    w = h = 512
    init = None
    seed = 0
    text = ""
    for node in graph.values():
        c = node["class_type"]; i = node["inputs"]
        if c == "EmptyLatentImage":
            w, h = i["width"], i["height"]
        if c == "KSampler":
            seed = i["seed"]
        if c == "CLIPTextEncode" and not text:
            text = i["text"]
    for nid in ("40",):
        nd = graph.get(nid)
        if nd and nd["class_type"] == "LoadImage" and nd["inputs"]["image"] in UPLOADS:
            init = Image.open(io.BytesIO(UPLOADS[nd["inputs"]["image"]])).convert("RGB")
            w, h = init.size
    if "empty background plate" in text:
        img = Image.new("RGB", (w, h), (40, 44, 60))
        d = ImageDraw.Draw(img)
        for k in range(8):
            d.rectangle([k * w // 8, h // 3 + (k % 3) * 20, k * w // 8 + w // 10, h], fill=(25, 25, 35))
        return img
    img = Image.new("RGB", (w, h), (200, 200, 200))
    d = ImageDraw.Draw(img)
    if init is not None:
        img = init.copy()
        d = ImageDraw.Draw(img)
        d.rectangle([4, 4, 20, 20], fill=(180, 30, 30))   # "redrawn" mark
        return img
    m = re.search(r"pose: ([^,]*)", text)
    x = (abs(hash(m.group(1) if m else str(seed))) % (w // 2)) + w // 4
    body = (30, 30, 36)
    if n % 7 == 0:
        body = (230, 40, 40)  # an off-model drawing QC should catch
    d.ellipse([x - 40, h // 4, x + 40, h // 4 + 80], fill=body)
    d.rectangle([x - 30, h // 4 + 80, x + 30, h - 40], fill=body)
    return img


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        p = self.path
        LOG.append("GET " + p.split("?")[0])
        if p == "/system_stats":
            return self._json({"system": {"comfyui_version": "0.3.99-mock"}, "devices": [{"name": "cuda:0 NVIDIA GeForce RTX 4070 (mock)", "vram_total": 12 * 1073741824}]})
        if p == "/object_info":
            return self._json(OBJECT_INFO)
        if p.startswith("/history/"):
            pid = p.split("/")[2]
            pr = PROMPTS.get(pid)
            if not pr or time.time() - pr["t"] < 0.4:
                return self._json({})
            return self._json({pid: {"status": {"status_str": "success", "completed": True, "messages": []},
                                     "outputs": {"9": {"images": [{"filename": pid + ".png", "subfolder": "", "type": "output"}]}}}})
        if p.startswith("/view"):
            fn = re.search(r"filename=([^&]*)", p).group(1)
            pid = fn.replace(".png", "")
            img = render(PROMPTS[pid]["graph"])
            buf = io.BytesIO(); img.save(buf, "PNG"); b = buf.getvalue()
            self.send_response(200); self.send_header("Content-Type", "image/png"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
            return
        if p.startswith("/api/tags"):
            return self._json({"models": [{"name": "qwen3:14b"}]})
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        p = self.path
        LOG.append("POST " + p)
        if p == "/upload/image":
            m = re.search(rb'filename="([^"]+)"\r\nContent-Type: [^\r]+\r\n\r\n', body)
            name = m.group(1).decode()
            start = m.end()
            end = body.rfind(b"\r\n--", 0, body.rfind(b'name="overwrite"'))
            UPLOADS[name] = body[start:end]
            return self._json({"name": name, "subfolder": "", "type": "input"})
        if p == "/prompt":
            j = json.loads(body)
            g = j["prompt"]
            # validate links + required inputs like ComfyUI would
            for nid, node in g.items():
                c = node["class_type"]
                if c not in OBJECT_INFO:
                    return self._json({"error": {"message": "Unknown node " + c}, "node_errors": {}}, 400)
                for k in OBJECT_INFO[c]["input"]["required"]:
                    if k not in node["inputs"]:
                        return self._json({"error": {"message": "missing input"}, "node_errors": {nid: {"class_type": c, "errors": [{"message": "Required input is missing", "details": k}]}}}, 400)
                for k, v in node["inputs"].items():
                    if isinstance(v, list) and len(v) == 2 and isinstance(v[0], str) and v[0] not in g:
                        return self._json({"error": {"message": "bad link %s.%s -> %s" % (nid, k, v[0])}}, 400)
                if c == "LoadImage" and node["inputs"]["image"] not in UPLOADS:
                    return self._json({"error": {"message": "image not uploaded: " + node["inputs"]["image"]}}, 400)
            pid = str(uuid.uuid4())
            PROMPTS[pid] = {"graph": g, "t": time.time()}
            with open("/tmp/mock_graphs.jsonl", "a") as f:
                f.write(json.dumps(g) + "\n")
            return self._json({"prompt_id": pid, "number": len(PROMPTS)})
        if p in ("/interrupt", "/queue"):
            return self._json({})
        if p == "/v1/messages":
            j = json.loads(body)
            with open("/tmp/mock_claude.jsonl", "a") as f:
                f.write(json.dumps({"tools": [t["name"] for t in j.get("tools", [])], "n_msgs": len(j["messages"]), "model": j["model"]}) + "\n")
            if self.headers.get("x-api-key") != "test-key":
                return self._json({"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}, 401)
            tools = [t["name"] for t in j.get("tools", [])]
            last = j["messages"][-1]["content"]
            text = " ".join(b.get("text", "") for b in last if b.get("type") == "text")
            if "qc_report" in tools:
                return self._json({"content": [{"type": "tool_use", "id": "t1", "name": "qc_report", "input": {
                    "summary": "Frame 5: the left hand has six fingers.", "problems": [{"frame": 5, "issue": "left hand has six fingers", "fix": "redraw the hand with five fingers"}]}}]})
            if "studio_actions" in tools:
                user = text.split("USER:\n")[-1]
                if "Create" in user:
                    inp = {"reply": "A slow walk in the rain, on twos; push in at the end.", "actions": [{"type": "create_shot", "shot": {
                        "name": "Rain walk", "duration_seconds": 1.0, "fps": 24, "exposure": 2, "action": "Mara walks through rain",
                        "environment": "rainy city street at night", "lighting": "sodium streetlight", "camera": "low angle medium shot",
                        "camera_preset": "push_in", "characters": ["Mara"], "background": "wet street, neon reflections", "separate_background": True,
                        "keys": [{"frame": 0, "kind": "key", "pose": "left foot contact", "expression": "grim"},
                                 {"frame": 6, "kind": "breakdown", "pose": "passing, weight up"},
                                 {"frame": 12, "kind": "key", "pose": "right foot contact", "expression": "grim"},
                                 {"frame": 23, "kind": "key", "pose": "left foot contact again", "expression": "grim"}]}}]}
                elif "Redraw frame" in user:
                    m = re.search(r"Redraw frame (\d+)", user)
                    inp = {"reply": "Fixing that hand.", "actions": [{"type": "revise_frames", "frames": [int(m.group(1))], "note": "anatomically correct hand, five fingers"}]}
                elif "red light" in user:
                    inp = {"reply": "Relighting.", "actions": [{"type": "update_shot", "changes": {"lighting": "dim red light"}, "regenerate": True}]}
                else:
                    inp = {"reply": "Hello, I'm your director.", "actions": []}
                return self._json({"content": [{"type": "tool_use", "id": "t1", "name": "studio_actions", "input": inp}]})
            return self._json({"content": [{"type": "text", "text": "heavy ink lines, low-key lighting, muted palette"}]})
        if p == "/api/chat":
            return self._json({"message": {"role": "assistant", "content": json.dumps({"reply": "local hello", "actions": []})}})
        self._json({"error": "not found"}, 404)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8199
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
