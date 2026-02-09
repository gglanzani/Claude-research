"""PDF OCR Comparison Tool.

A web app that displays an original PDF and a Typst-compiled PDF side by side,
with an editable Typst source panel and a Gemini chat interface for generating
sed rules to batch-modify the Typst source.
"""

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import typst
from flask import Flask, jsonify, request, send_file, send_from_directory
from google import genai

app = Flask(__name__, static_folder="static", template_folder="templates")

# Global state
STATE = {
    "original_pdf": None,  # path to original PDF
    "typst_path": None,  # path to the .typ file on disk
    "typst_source": "",  # current typst source (possibly edited)
    "compiled_pdf": None,  # path to last compiled PDF bytes
    "work_dir": None,  # temp dir for compilation artifacts
}


def compile_typst(source: str) -> bytes:
    """Compile typst source to PDF bytes."""
    # Write source to the working directory so relative imports work
    work_dir = STATE["work_dir"]
    typ_file = os.path.join(work_dir, "main.typ")
    with open(typ_file, "w") as f:
        f.write(source)
    return typst.compile(typ_file)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.route("/")
def index():
    return send_from_directory("templates", "index.html")


@app.route("/api/original-pdf")
def original_pdf():
    if STATE["original_pdf"] is None:
        return "No PDF loaded", 404
    return send_file(STATE["original_pdf"], mimetype="application/pdf")


@app.route("/api/compiled-pdf")
def compiled_pdf():
    try:
        pdf_bytes = compile_typst(STATE["typst_source"])
        return pdf_bytes, 200, {"Content-Type": "application/pdf"}
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/typst-source", methods=["GET"])
def get_typst_source():
    return jsonify({"source": STATE["typst_source"]})


@app.route("/api/typst-source", methods=["POST"])
def update_typst_source():
    data = request.get_json()
    STATE["typst_source"] = data["source"]
    return jsonify({"ok": True})


@app.route("/api/apply-sed", methods=["POST"])
def apply_sed():
    """Apply a list of sed-style s/pattern/replacement/flags rules."""
    data = request.get_json()
    rules = data.get("rules", [])
    source = STATE["typst_source"]
    applied = []
    for rule in rules:
        rule = rule.strip()
        if not rule:
            continue
        # Parse sed s-command: s/pat/repl/flags
        # Support any single-char delimiter after 's'
        if len(rule) < 4 or rule[0] != "s":
            applied.append({"rule": rule, "error": "Invalid sed rule format"})
            continue
        delim = rule[1]
        parts = rule[2:].split(delim)
        if len(parts) < 2:
            applied.append({"rule": rule, "error": "Could not parse pattern/replacement"})
            continue
        pattern = parts[0]
        replacement = parts[1]
        flags_str = parts[2] if len(parts) > 2 else ""
        re_flags = 0
        count = 1
        if "g" in flags_str:
            count = 0  # replace all
        if "i" in flags_str:
            re_flags |= re.IGNORECASE
        try:
            new_source = re.sub(pattern, replacement, source, count=count, flags=re_flags)
            changes = new_source != source
            source = new_source
            applied.append({"rule": rule, "ok": True, "changes": changes})
        except re.error as e:
            applied.append({"rule": rule, "error": str(e)})
    STATE["typst_source"] = source
    return jsonify({"source": source, "applied": applied})


@app.route("/api/chat", methods=["POST"])
def chat():
    """Send a message to Gemini and get sed rules back."""
    data = request.get_json()
    user_message = data.get("message", "")
    api_key = data.get("api_key", "") or os.environ.get("GEMINI_API_KEY", "")

    if not api_key:
        return jsonify({"error": "No Gemini API key provided. Set GEMINI_API_KEY or enter it in the UI."}), 400

    client = genai.Client(api_key=api_key)

    system_prompt = (
        "You are an expert at writing sed substitution rules for editing Typst documents. "
        "The user will describe modifications they want to make to a Typst (.typ) document. "
        "You should respond with sed-style substitution rules in the format: s/pattern/replacement/flags\n"
        "Use Python regex syntax (since these will be applied via Python re.sub).\n"
        "Put each rule on its own line. You may include brief explanations as comments starting with #.\n"
        "Only output rules and comments, nothing else.\n\n"
        "Here is the current Typst source:\n"
        "```typst\n"
        f"{STATE['typst_source']}\n"
        "```"
    )

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[
                {"role": "user", "parts": [{"text": system_prompt + "\n\nUser request: " + user_message}]},
            ],
        )
        return jsonify({"response": response.text})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/save", methods=["POST"])
def save_to_disk():
    """Save current typst source back to the original file."""
    if STATE["typst_path"] is None:
        return jsonify({"error": "No typst file path set"}), 400
    with open(STATE["typst_path"], "w") as f:
        f.write(STATE["typst_source"])
    return jsonify({"ok": True, "path": STATE["typst_path"]})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="PDF OCR Comparison Tool")
    parser.add_argument("original_pdf", help="Path to the original PDF file")
    parser.add_argument("typst_file", help="Path to the Typst (.typ) OCR result file")
    parser.add_argument("--port", type=int, default=5000, help="Port to run the server on")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to")
    parser.add_argument("--gemini-key", default=None, help="Gemini API key (or set GEMINI_API_KEY env var)")
    args = parser.parse_args()

    original_pdf = os.path.abspath(args.original_pdf)
    typst_file = os.path.abspath(args.typst_file)

    if not os.path.exists(original_pdf):
        raise FileNotFoundError(f"PDF not found: {original_pdf}")
    if not os.path.exists(typst_file):
        raise FileNotFoundError(f"Typst file not found: {typst_file}")

    # Set up working directory: copy typst file's directory contents so
    # relative imports/images work
    typst_dir = os.path.dirname(typst_file)
    work_dir = tempfile.mkdtemp(prefix="pdf-ocr-compare-")
    # Copy everything from the typst directory into the work dir
    for item in os.listdir(typst_dir):
        src = os.path.join(typst_dir, item)
        dst = os.path.join(work_dir, item)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    with open(typst_file, "r") as f:
        typst_source = f.read()

    STATE["original_pdf"] = original_pdf
    STATE["typst_path"] = typst_file
    STATE["typst_source"] = typst_source
    STATE["work_dir"] = work_dir

    if args.gemini_key:
        os.environ["GEMINI_API_KEY"] = args.gemini_key

    print(f"Original PDF: {original_pdf}")
    print(f"Typst file:   {typst_file}")
    print(f"Work dir:     {work_dir}")
    print(f"Open http://{args.host}:{args.port} in your browser")

    app.run(host=args.host, port=args.port, debug=True)


if __name__ == "__main__":
    main()
