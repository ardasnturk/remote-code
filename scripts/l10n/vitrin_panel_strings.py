#!/usr/bin/env python3
"""Writes RemoteCodeiOS/Vitrin/Panel/Vitrin.xcstrings, the table `L.t` reads in the Vitrin tab.

Vitrin for Mac's catalog holds the words, so the panel says the same thing in the same 10 languages. Only keys the code
in RemoteCodeiOS/Vitrin can reach are kept: every string literal that is a key, everything under a literal in front of
an interpolation ("asc.key.step\\(n)"), and the prefixes keys are built from at runtime. NEW_KEYS are the phone's own.

Run from the repository root:  python3 scripts/l10n/vitrin_panel_strings.py [path to Vitrin's checkout]
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vitrin_project_keys import PROJECT_KEYS  # The project pages' own words.

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCES = os.path.join(ROOT, "RemoteCodeiOS", "Vitrin")
OUTPUT = os.path.join(SOURCES, "Panel", "Vitrin.xcstrings")
CATALOG = "apps/VitrinMac/VitrinMac/Resources/Localizable.xcstrings"
LANGUAGES = ["en", "tr", "de", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-Hans"]
# Keys built at runtime (AscText, AscInfo, TeamPage, AscAreas, AppOverviewView).
PREFIXES = ("asc.field.", "asc.flag.", "asc.group.", "asc.tab.", "ascgroup.", "ascState.", "enum.", "info.", "team.")

NEW_KEYS = {
    "vitrin.notConnected": ["Your Mac is not connected", "Mac'in bağlı değil", "Dein Mac ist nicht verbunden", "Tu Mac no está conectado", "Votre Mac n’est pas connecté", "Il tuo Mac non è connesso", "Macが接続されていません", "Mac이 연결되어 있지 않습니다", "Seu Mac não está conectado", "你的 Mac 未连接"],
    "vitrin.chooseFolder": ["Choose a folder", "Klasör seç", "Ordner auswählen", "Elegir una carpeta", "Choisir un dossier", "Scegli una cartella", "フォルダを選択", "폴더 선택", "Escolher uma pasta", "选择文件夹"],
    "vitrin.chooseFile": ["Choose a file", "Dosya seç", "Datei auswählen", "Elegir un archivo", "Choisir un fichier", "Scegli un file", "ファイルを選択", "파일 선택", "Escolher um arquivo", "选择文件"],
    "vitrin.cancel": ["Cancel", "Vazgeç", "Abbrechen", "Cancelar", "Annuler", "Annulla", "キャンセル", "취소", "Cancelar", "取消"],
    "vitrin.addThisFolder": ["Add", "Ekle", "Hinzufügen", "Añadir", "Ajouter", "Aggiungi", "追加", "추가", "Adicionar", "添加"],
    "vitrin.useThisFolder": ["Use this folder", "Bu klasörü kullan", "Diesen Ordner verwenden", "Usar esta carpeta", "Utiliser ce dossier", "Usa questa cartella", "このフォルダを使用", "이 폴더 사용", "Usar esta pasta", "使用此文件夹"],
    "vitrin.projects": ["Projects", "Projeler", "Projekte", "Proyectos", "Projets", "Progetti", "プロジェクト", "프로젝트", "Projetos", "项目"],
    "vitrin.noProjects": ["No projects yet", "Henüz proje yok", "Noch keine Projekte", "Aún no hay proyectos", "Aucun projet pour l’instant", "Ancora nessun progetto", "プロジェクトはまだありません", "아직 프로젝트가 없습니다", "Ainda não há projetos", "还没有项目"],
    "vitrin.apps": ["Apps", "Uygulamalar", "Apps", "Apps", "Apps", "App", "アプリ", "앱", "Apps", "App"],
    "vitrin.team": ["Team", "Ekip", "Team", "Equipo", "Équipe", "Team", "チーム", "팀", "Equipe", "团队"],
    "vitrin.addProject": ["Add project", "Proje ekle", "Projekt hinzufügen", "Añadir proyecto", "Ajouter un projet", "Aggiungi progetto", "プロジェクトを追加", "프로젝트 추가", "Adicionar projeto", "添加项目"],
    "vitrin.removeProject": ["Remove from Vitrin", "Vitrin'den kaldır", "Aus Vitrin entfernen", "Quitar de Vitrin", "Retirer de Vitrin", "Rimuovi da Vitrin", "Vitrinから削除", "Vitrin에서 제거", "Remover do Vitrin", "从 Vitrin 移除"],
    "vitrin.folderMissing": ["This folder is missing", "Bu klasör bulunamıyor", "Dieser Ordner fehlt", "Falta esta carpeta", "Ce dossier est introuvable", "Questa cartella non si trova", "このフォルダが見つかりません", "이 폴더를 찾을 수 없습니다", "Esta pasta não foi encontrada", "找不到此文件夹"],
    "vitrin.updateVitrin": ["Update Vitrin on your Mac", "Mac'indeki Vitrin'i güncelle", "Vitrin auf deinem Mac aktualisieren", "Actualizar Vitrin en tu Mac", "Mettre à jour Vitrin sur votre Mac", "Aggiorna Vitrin sul tuo Mac", "MacのVitrinをアップデート", "Mac의 Vitrin 업데이트", "Atualizar o Vitrin no seu Mac", "更新 Mac 上的 Vitrin"],
    "vitrin.updating": ["Updating Vitrin on your Mac…", "Mac'indeki Vitrin güncelleniyor…", "Vitrin wird auf deinem Mac aktualisiert …", "Actualizando Vitrin en tu Mac…", "Mise à jour de Vitrin sur votre Mac…", "Aggiornamento di Vitrin sul tuo Mac…", "MacのVitrinをアップデートしています…", "Mac의 Vitrin을 업데이트하는 중…", "Atualizando o Vitrin no seu Mac…", "正在更新 Mac 上的 Vitrin…"],
    "vitrin.installingAsc": ["Installing asc on your Mac…", "asc Mac'ine kuruluyor…", "asc wird auf deinem Mac installiert …", "Instalando asc en tu Mac…", "Installation d’asc sur votre Mac…", "Installazione di asc sul tuo Mac…", "Macにascをインストールしています…", "Mac에 asc를 설치하는 중…", "Instalando o asc no seu Mac…", "正在 Mac 上安装 asc…"],
    "vitrin.signedInAs": ["Signed in as {id}", "{id} olarak giriş yapıldı", "Angemeldet als {id}", "Sesión iniciada como {id}", "Connecté en tant que {id}", "Accesso eseguito come {id}", "{id} としてサインイン中", "{id}(으)로 로그인됨", "Conectado como {id}", "已登录为 {id}"],
    "vitrin.ads.keyOnMac": [
        "The key pair has to be on your Mac, and only Vitrin for Mac can make it: open Team > Apple Ads there once and paste its public key into Apple Ads (Account Settings > API, signed in as the API user). Then choose the private key here. A PEM key of your own works too.",
        "Anahtar çifti Mac'inde olmalı ve onu yalnızca Vitrin for Mac oluşturabilir: orada bir kez Ekip > Apple Ads sayfasını aç ve açık anahtarı Apple Ads'e yapıştır (API kullanıcısıyla oturum açıp Hesap Ayarları > API). Sonra özel anahtarı burada seç. Kendi PEM anahtarın da olur.",
        "Das Schlüsselpaar muss auf deinem Mac liegen, und nur Vitrin für Mac kann es erzeugen: Öffne dort einmal Team > Apple Ads und füge den öffentlichen Schlüssel in Apple Ads ein (Account Settings > API, als API-Benutzer angemeldet). Wähle dann hier den privaten Schlüssel aus. Ein eigener PEM-Schlüssel geht auch.",
        "El par de claves debe estar en tu Mac y solo Vitrin para Mac puede crearlo: abre allí una vez Equipo > Apple Ads y pega su clave pública en Apple Ads (Account Settings > API, con la sesión del usuario de API). Luego elige aquí la clave privada. También sirve una clave PEM propia.",
        "La paire de clés doit se trouver sur votre Mac, et seul Vitrin pour Mac peut la créer : ouvrez-y une fois Équipe > Apple Ads et collez sa clé publique dans Apple Ads (Account Settings > API, connecté comme utilisateur API). Choisissez ensuite la clé privée ici. Une clé PEM personnelle convient aussi.",
        "La coppia di chiavi deve trovarsi sul tuo Mac e solo Vitrin per Mac può crearla: apri lì una volta Team > Apple Ads e incolla la chiave pubblica in Apple Ads (Account Settings > API, con l’accesso dell’utente API). Poi scegli qui la chiave privata. Va bene anche una tua chiave PEM.",
        "キーペアはMac上に必要で、作成できるのはVitrin for Macだけです。Macで一度「チーム」>「Apple Ads」を開き、公開鍵をApple Ads(API ユーザーでサインインして Account Settings > API)に貼り付けてから、ここで秘密鍵を選択してください。自分のPEM鍵も使えます。",
        "키 쌍은 Mac에 있어야 하며 Vitrin for Mac만 만들 수 있습니다. Mac에서 팀 > Apple Ads를 한 번 열고 공개 키를 Apple Ads(API 사용자로 로그인 후 Account Settings > API)에 붙여넣은 다음, 여기서 개인 키를 선택하세요. 직접 만든 PEM 키도 사용할 수 있습니다.",
        "O par de chaves precisa estar no seu Mac, e só o Vitrin para Mac consegue criá-lo: abra lá uma vez Equipe > Apple Ads e cole a chave pública no Apple Ads (Account Settings > API, conectado como usuário de API). Depois escolha a chave privada aqui. Uma chave PEM sua também serve.",
        "密钥对必须位于你的 Mac 上,且只有 Vitrin for Mac 能创建:在 Mac 上打开一次“团队 > Apple Ads”,把公钥粘贴到 Apple Ads(以 API 用户登录后进入 Account Settings > API),然后在这里选择私钥。你自己的 PEM 密钥也可以。",
    ],
    "vitrin.ads.keyPath": ["Private key on your Mac", "Mac'indeki özel anahtar", "Privater Schlüssel auf deinem Mac", "Clave privada en tu Mac", "Clé privée sur votre Mac", "Chiave privata sul tuo Mac", "Mac上の秘密鍵", "Mac의 개인 키", "Chave privada no seu Mac", "Mac 上的私钥"],
}


def reachable(catalog):
    keys = set()
    for folder, _, files in os.walk(SOURCES):
        for name in files:
            if not name.endswith(".swift"):
                continue
            source = open(os.path.join(folder, name), encoding="utf-8").read()
            # By pattern, not by pairing quotes: keys also sit inside interpolations of other literals.
            keys.update(key for key in re.findall(r'"([\w.\-]+)"', source) if key in catalog)
            for prefix in re.findall(r'"([\w.\-]{4,})\\\(', source):
                keys.update(key for key in catalog if key.startswith(prefix))
    keys.update(key for key in catalog if key.startswith(PREFIXES))
    return keys


def main():
    vitrin = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(ROOT), "auto-asc-metadata")
    source = json.load(open(os.path.join(vitrin, CATALOG), encoding="utf-8"))
    catalog = source["strings"]
    strings = {key: catalog[key] for key in reachable(catalog)}
    new_keys = {**NEW_KEYS, **PROJECT_KEYS}
    for key, values in new_keys.items():
        assert len(values) == len(LANGUAGES), key
        strings[key] = {"localizations": {language: {"stringUnit": {"state": "translated", "value": value}} for language, value in zip(LANGUAGES, values)}}
    output = {"sourceLanguage": source["sourceLanguage"], "strings": dict(sorted(strings.items())), "version": source["version"]}
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        json.dump(output, handle, ensure_ascii=False, indent=2, separators=(",", " : "))
        handle.write("\n")
    print(f"{len(strings)} keys of {len(catalog)}, {len(new_keys)} new")


if __name__ == "__main__":
    main()
