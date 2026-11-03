"""
Application de démonstration VOLONTAIREMENT VULNÉRABLE.

Objectif : vérifier que chaque scan du template remonte bien une alerte.
NE JAMAIS déployer ce code ailleurs que sur un poste local ou un runner CI.

Vulnérabilités introduites (et outil censé les détecter) :
  /user    injection SQL                       -> CodeQL
  /ping    injection de commande               -> CodeQL
  /hello   XSS réfléchi                        -> CodeQL
  /file    path traversal                      -> CodeQL
  /import  désérialisation YAML dangereuse     -> CodeQL + Dependabot / Dependency Review (PyYAML 5.3.1)
  API_KEY  secret en dur (faux, non valide)    -> Gitleaks
  debug    mode debug Flask activé             -> CodeQL
  cookie   cookie de session sans HttpOnly     -> ZAP (règle 10010, bloquante)
"""

import os
import sqlite3
import subprocess

import yaml
from flask import Flask, make_response, request

app = Flask(__name__)

# Faux secret volontaire pour la démonstration Gitleaks (valeur aléatoire, non valide).
API_KEY = "x9Kf2Lq7Vb4Zt8Rw1Mn6Yp3Hd5Gs0Jc"

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


def get_db():
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE users (id INTEGER, name TEXT, email TEXT)")
    db.execute("INSERT INTO users VALUES (1, 'alice', 'alice@example.com')")
    db.execute("INSERT INTO users VALUES (2, 'bob', 'bob@example.com')")
    return db


@app.route("/")
def index():
    resp = make_response(
        "<h1>Demo app</h1>"
        "<ul>"
        "<li><a href='/user?id=1'>/user?id=1</a></li>"
        "<li><a href='/hello?name=world'>/hello?name=world</a></li>"
        "<li><a href='/ping?host=127.0.0.1'>/ping?host=127.0.0.1</a></li>"
        "<li><a href='/file?name=welcome.txt'>/file?name=welcome.txt</a></li>"
        "</ul>"
    )
    # Vulnérable : cookie de session sans HttpOnly ni Secure.
    resp.set_cookie("session_id", "demo-session", httponly=False)
    return resp


@app.route("/user")
def user():
    user_id = request.args.get("id", "1")
    # Vulnérable : injection SQL (concaténation de l'entrée utilisateur).
    query = "SELECT id, name, email FROM users WHERE id = " + user_id
    rows = get_db().execute(query).fetchall()
    return {"results": rows}


@app.route("/ping")
def ping():
    host = request.args.get("host", "127.0.0.1")
    # Vulnérable : injection de commande (shell=True + entrée utilisateur).
    output = subprocess.run("ping -c 1 " + host, shell=True, capture_output=True, text=True)
    return "<pre>" + output.stdout + "</pre>"


@app.route("/hello")
def hello():
    name = request.args.get("name", "world")
    # Vulnérable : XSS réfléchi (entrée renvoyée sans encodage).
    return make_response("<p>Hello " + name + "</p>")


@app.route("/file")
def read_file():
    name = request.args.get("name", "welcome.txt")
    # Vulnérable : path traversal (ex : ?name=../../../../etc/passwd).
    with open(os.path.join(DATA_DIR, name), encoding="utf-8") as f:
        return "<pre>" + f.read() + "</pre>"


@app.route("/import", methods=["POST"])
def import_config():
    # Vulnérable : yaml.load avec un Loader non sûr -> exécution de code arbitraire.
    config = yaml.load(request.get_data(as_text=True), Loader=yaml.Loader)
    return {"keys": list(config.keys()) if isinstance(config, dict) else []}


if __name__ == "__main__":
    # Vulnérable : mode debug activé et écoute sur toutes les interfaces.
    app.run(host="0.0.0.0", port=8080, debug=True)
