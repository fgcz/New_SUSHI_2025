#!/usr/bin/env python3
"""
build_omakase_prototype_deck.py — generate the OMAKASE prototype deck, JA + EN.

Why a generator instead of two hand-written HTML files
------------------------------------------------------
The FGCZ presentation format (L1 `fgcz_presentation_format`) requires the JA and
the EN deck to have *identical geometry* — only the language strings differ. This
deck is figure-driven: every slide carries one SVG diagram, and keeping ten pairs
of hand-written SVGs in lockstep by editing two files is exactly the failure this
format warns about. So the geometry lives once, in Python, and the strings live in
one bilingual table. Edit this script, re-run it, never edit the HTML by hand.

    python3 docs/presentations/build_omakase_prototype_deck.py
    python3 scripts/html_artifact_check/check.py docs/presentations/omakase_prototype_*.html

Naming, decided 2026-09-12
--------------------------
The internal code names do not appear in this deck. The report keeps them.

    SUSHI (the platform, its apps)  ->  Omakase-Platform / Omakase-App
    SUSHI-MCP-server               ->  Omakase-MCP-Server
    Omics-Studio (the REST API)    ->  Omakase-backend-API-server

Cover image
-----------
Taken from the report (`docs/omakase-prototype-20260909-ja.html`), not from
`log/omakase_image.png` — `log/` is gitignored, so sourcing it from the report is
what makes this build reproducible from a fresh clone. Same 1672x941 JPEG, so the
deck and the report show the same picture.
"""

from __future__ import annotations

import base64
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
REPORT = os.path.join(DOCS, 'omakase-prototype-20260909-ja.html')

# ------------------------------------------------------------------ palette --
NAVY = '#003c68'
DARK = '#001428'
ORANGE = '#ea6b13'
CYAN = '#0099cc'
CYAN_L = '#4dc9f6'
GREY = '#545e69'
GREY_L = '#9aa5b1'
BG = '#f5f7fa'
WHITE = '#ffffff'
RED = '#c2402a'
PANEL = '#f9fafb'

CANVAS_W, CANVAS_H = 1180, 380


# ------------------------------------------------------------------ helpers --
def esc(s: str) -> str:
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def anim(cls: str, d: float) -> str:
    return f' class="{cls}" style="--d:{d:g}s"'


def txt(x, y, s, fs=14, fill=NAVY, anchor='start', weight=None, mono=False,
        op=None):
    a = [f'x="{x:g}"', f'y="{y:g}"', f'font-size="{fs:g}"', f'fill="{fill}"']
    if anchor != 'start':
        a.append(f'text-anchor="{anchor}"')
    if weight:
        a.append(f'font-weight="{weight}"')
    if mono:
        a.append('font-family="JetBrains Mono, Consolas, monospace"')
    if op is not None:
        a.append(f'opacity="{op:g}"')
    return f'<text {" ".join(a)}>{esc(s)}</text>'


def rect(x, y, w, h, fill=PANEL, stroke=NAVY, sw=2, rx=12, dash=None, op=None):
    a = [f'x="{x:g}"', f'y="{y:g}"', f'width="{w:g}"', f'height="{h:g}"',
         f'rx="{rx:g}"', f'fill="{fill}"', f'stroke="{stroke}"',
         f'stroke-width="{sw:g}"']
    if dash:
        a.append(f'stroke-dasharray="{dash}"')
    if op is not None:
        a.append(f'opacity="{op:g}"')
    return f'<rect {" ".join(a)}/>'


def box(x, y, w, h, title, sub=None, sub2=None, d=0.0, fill=PANEL, stroke=NAVY,
        dash=None, tfs=16, sfs=11.5, tcol=NAVY, scol=GREY, sw=2, rx=12,
        extra='', cls='an'):
    """One labelled rounded box. Up to three centred lines."""
    cx, mid = x + w / 2, y + h / 2
    body = [rect(x, y, w, h, fill=fill, stroke=stroke, sw=sw, rx=rx, dash=dash)]
    if sub2 is not None:
        body.append(txt(cx, mid - 13, title, tfs, tcol, 'middle', '700'))
        body.append(txt(cx, mid + 6, sub, sfs, scol, 'middle'))
        body.append(txt(cx, mid + 23, sub2, sfs, scol, 'middle'))
    elif sub is not None:
        body.append(txt(cx, mid - 4, title, tfs, tcol, 'middle', '700'))
        body.append(txt(cx, mid + 16, sub, sfs, scol, 'middle'))
    else:
        body.append(txt(cx, mid + 6, title, tfs, tcol, 'middle', '700'))
    return f'<g{anim(cls, d)}>' + ''.join(body) + extra + '</g>'


def arrow(x1, y1, x2, y2, color=ORANGE, marker='arr', d=0.0, sw=2.5):
    """A drawn-in connector. Animation: the stroke paints itself."""
    return (f'<path class="draw" style="--d:{d:g}s" d="M{x1:g} {y1:g} L{x2:g} {y2:g}" '
            f'pathLength="1" fill="none" stroke="{color}" stroke-width="{sw:g}" '
            f'marker-end="url(#{marker})"/>')


def dashed(x1, y1, x2, y2, color=GREY_L, marker='arrGy', d=0.0, sw=2.5):
    return (f'<path{anim("an", d)} d="M{x1:g} {y1:g} L{x2:g} {y2:g}" fill="none" '
            f'stroke="{color}" stroke-width="{sw:g}" stroke-dasharray="6 5" '
            f'marker-end="url(#{marker})"/>')


def bar(x, y, w, h, fill, d=0.0, rx=5, stroke='none', sw=0):
    a = [f'x="{x:g}"', f'y="{y:g}"', f'width="{w:g}"', f'height="{h:g}"',
         f'rx="{rx:g}"', f'fill="{fill}"']
    if stroke != 'none':
        a += [f'stroke="{stroke}"', f'stroke-width="{sw:g}"']
    return f'<rect class="grow" style="--d:{d:g}s" {" ".join(a)}/>'


def tick(ok: bool, cx, cy, d=0.0):
    """A round status badge: navy check = done, orange cross = still missing."""
    if ok:
        return (f'<g{anim("an", d)}><circle cx="{cx:g}" cy="{cy:g}" r="13" fill="{NAVY}"/>'
                f'<path d="M{cx-6:g} {cy:g} l4 4.5 l8 -9" fill="none" stroke="#fff" '
                f'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></g>')
    return (f'<g class="an pulse" style="--d:{d:g}s"><circle cx="{cx:g}" cy="{cy:g}" r="13" '
            f'fill="{ORANGE}"/><path d="M{cx-5:g} {cy-5:g} l10 10 M{cx+5:g} {cy-5:g} l-10 10" '
            f'fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/></g>')


def person(cx, cy, d=0.0, color=NAVY, scale=1.0):
    r, hw, hh = 6 * scale, 9 * scale, 9 * scale
    return (f'<g{anim("an", d)}><circle cx="{cx:g}" cy="{cy - hh:g}" r="{r:g}" fill="{color}"/>'
            f'<path d="M{cx - hw:g} {cy + hh:g} a{hw:g} {hh:g} 0 0 1 {2 * hw:g} 0 z" '
            f'fill="{color}"/></g>')


def svg(body, title, sid, w=CANVAS_W, h=CANVAS_H):
    return (f'<svg class="fig" viewBox="0 0 {w} {h}" role="img" aria-labelledby="{sid}">'
            f'<title id="{sid}">{esc(title)}</title>{body}</svg>')


# --------------------------------------------------------------- the strings --
# One table, two languages, same keys. Anything that is a measurement carries its
# denominator; anything that is not yet built says so.
TX = {
 'ja': {
  'lang': 'ja', 'other': 'omakase_prototype_en.html', 'other_label': 'English version',
  'doctitle': 'OMAKASE システム プロトタイプ — 2026-09-16',
  'hint': '← → で移動 · R で再生 · F で全画面',

  'cover_title': 'OMAKASE',
  'cover_sub': 'システム プロトタイプ — オーダーが完了してから、解析が終わるまで',
  'cover_acro': 'Omics Metadata Automated Knowledge-based Analysis Suggestion &amp; Execution（名称は暫定）',
  'cover_catch': 'ルールが決め、AI が助け、人が出す',
  'cover_meta': ['2026-09-16 · FGCZ Genomics',
                 'fgcz-h-083（隔離されたテスト DB）· 本番への書き込みゼロ',
                 '本文の数値はすべて 2026-09-09 〜 09-11 の実測'],

  's2_title': '今日、オーダーが終わっても、誰にも何も起きない',
  's2_fig': '現状。オーダーの状態変更に反応するものはなく、解析は人が1アプリずつ起動している。',
  's2_a': '担当者', 's2_a_s': '品質確認を終える',
  's2_b': 'B-Fabric', 's2_b_s': 'status を processed にする',
  's2_c': '反応するものが無い', 's2_c_s': '誰にも通知されない',
  's2_row2': 'そして解析そのものも、1アプリずつ人が起動している',
  's2_app1': 'STAR', 's2_app2': 'FeatureCounts', 's2_app3': 'CountQC',
  's2_wait': '人が待って、人が次を起動',
  's2_chips': [('1 463 件', '過去12か月のシーケンスオーダー'),
               ('71 %', '実解析 426 件のうち 2 段以上 = 304 件'),
               ('17 %', '履歴から最有力の連鎖を当てられた割合 71/421')],
  's2_src': '実測: 2026-08-20（オーダー数）· 2026-09-10（連鎖の深さ・的中率）本番 DB に対する読み取りのみ',

  's3_title': 'OMAKASE は、その日の注文から献立を組んで「提案」する',
  's3_fig': '6 つの段。青の丸は実機で動くもの、橙の×はまだ無いもの。',
  's3_steps': [('オーダー完了', '検出'), ('データセット', '特定'), ('レシピ', '作成'),
               ('人が承認', 'ここが関門'), ('献立を実行', '並列・停止保証'),
               ('通知', '結果を届ける')],
  's3_done': [True, True, False, True, True, False],
  's3_note': 'アプリは作らない。既存のアプリを選んで順序を付ける。参照ゲノムの選択もレシピの中で決まる。',
  's3_legend': [('青 = 実機で動く', NAVY), ('橙 = まだ無い', ORANGE),
                ('太線 = 人の判断', GREY)],
  's3_catch': '— ルールが決め、AI が助け、人が出す —',
  's3_src': '実測: 2026-09-11 fgcz-h-083（隔離テスト DB）· 残り2段は未実装',

  's4_title': '取りこぼさない — 監視ではなく、集合の引き算',
  's4_fig': '毎回すべての集合を取り、自分の処理済みを引く。差が新しいオーダー。',
  's4_setA': 'B-Fabric に今ある', 's4_setA2': 'status = processed の全集合',
  's4_setB': 'OMAKASE が', 's4_setB2': '処理済みとして持つ集合',
  's4_res': '新しいオーダー', 's4_res2': 'これだけを扱う',
  's4_minus': '−', 's4_eq': '=',
  's4_chips': [('0.6 – 2.1 秒', '全集合の問い合わせ 1 回（4 回計測）'),
               ('30 件', '本番で processed になったオーダー、通算'),
               ('取りこぼし 0', '1 日止まっても、次の1回で追いつく')],
  's4_note': '通知を受け取る方式のほうが取りこぼす。1 通落ちたら、それは永久に失われる。',
  's4_src': '実測: 2026-09-10 本番 B-Fabric に対する読み取りのみ · statusmodifiedafter は存在せず、webhook も無い',

  's5_title': 'オーダーから解析対象へ — 82 件を 1 件に絞る',
  's5_fig': 'データセットの絞り込み。条件を満たすものが無ければ、推測せず断る。',
  's5_f': [('プロジェクトの全データセット', '82'),
           ('Order Id 列を持つ', '62'),
           ('order_id が単一の値', '3'),
           ('親を持たない = 生データ', '1')],
  's5_out': 'dataset 9', 's5_out2': 'これが解析対象',
  's5_dec': '該当なし → 断る', 's5_dec2': 'DECLINED / 終了コード 3',
  's5_chips': [('7 回', '詳細を開いた回数。82 件を全部開けば 82 回'),
               ('order 35773', '人が processed にし、watcher が本当に検出し、そして断った'),
               ('order 35755', '→ dataset 9。こちらは通る')],
  's5_src': '実測: 2026-09-11 · 対応付けは B-Fabric ではなく Omakase-Platform 側で導出される',

  's6_title': '参照ゲノムは、レシピの中で選ぶ。人は打ち込まない',
  's6_fig': '参照ゲノムの選び方。選べない 4 つの場合は、推測せず提案しない。',
  's6_in': 'データセットの Species 列', 's6_in2': '例: Mus musculus',
  's6_mid': '/srv/GT/reference-favorite', 's6_mid2': '収載は 5 種、それぞれ 1 ビルド',
  's6_out': '選ばれた参照ゲノム', 's6_out2': '承認者はこの実パスを見る',
  's6_path': 'Mus_musculus/GENCODE/GRCm39/…/Release_M37',
  's6_refuse': ['Species が無い', 'NA / 空欄', '2 種が混在', '収載されていない種'],
  's6_refuse_to': '提案しない（4 つとも、これが正しい動作）',
  's6_chips': [('42 752 リード', '10 万リード中、遺伝子に割り当てられた数'),
               ('6 795 遺伝子', 'ENSMUSG — マウスの識別子。選んだゲノムが合っていた証拠'),
               ('2 段目は選び直さない', 'STAR の出力が Species と refBuild を列として運ぶ')],
  's6_src': '実測: 2026-09-11 · 2026-08-07 の速度試験は同じマウスデータにシロイヌナズナを当てていた。あれを前例にしてはいけない',

  's7_title': '人が承認するまで、1 件も投入されない',
  's7_fig': '提案の中身と、人が選べる 3 つの答え。承認の前に投入は起きない。',
  's7_card': '提案', 's7_card_lines': ['どのアプリを', 'どの順序で',
                                        'どのパラメータで', 'なぜそれを選んだか'],
  's7_gate': '人の承認',
  's7_ok': '受け入れる', 's7_ok2': 'そのまま投入',
  's7_edit': '直す', 's7_edit2': '直した形で投入',
  's7_no': '却下する', 's7_no2': '何も投入されない',
  's7_chips': [('17 %', '履歴から最有力を当てられた割合 71/421。だから提案であって実行ではない'),
               ('3 値で記録', '受け入れ / 修正 / 却下 — 判定はモデルではなく人が付ける'),
               ('自動承認なし', 'プロトタイプでは毎回、人が明示的に承認する')],
  's7_src': '実測: 2026-09-10 本番の履歴 421 オーダー · 提案の採否はこのあと精度の測定に使う',

  's8_title': '連鎖は並列で走る — 実測 6 分 31 秒',
  's8_fig': '2026-09-11 15:49–15:55 の実測。直列との比較は同じ時間軸で描いてある。',
  's8_rows': ['FastQC', 'FastqScreen', 'STAR ×2', 'FeatureCounts ×2'],
  's8_done': 'DONE 6:31',
  's8_serial': '直列に走らせた場合の合計 12:13',
  's8_ann1': '3 つは 41 秒以内に出そろう',
  's8_ann2': 'STAR が完了を報告した 22 秒後に投入。FastQC はまだ走っている',
  's8_axis': '分',
  's8_chips': [('6:31 / 12:13', '並列の実測 / 直列に足した場合'),
               ('3:25', 'クリティカルパス STAR → FeatureCounts'),
               ('5:28', '最長は FastQC。ただし誰も待たない葉')],
  's8_src': '実測: 2026-09-11 fgcz-h-083 · 最後のジョブ完了から DONE 判定までの 63 秒はポーリング間隔',

  's9_title': '止まることが機能 — 失敗した先へは投入しない',
  's9_fig': '正常系と、わざと失敗させた系。後者では 2 段目の投入記録が存在しない。',
  's9_ok_lane': '正常系',
  's9_ng_lane': 'わざと失敗させた系',
  's9_ok1': 'STAR', 's9_ok1s': 'COMPLETED',
  's9_ok2': 'FeatureCounts', 's9_ok2s': '完了を見てから投入',
  's9_ok3': 'DONE', 's9_ok3s': '11:59:39',
  's9_ng1': 'STAR', 's9_ng1s': 'FAILED — 30 秒',
  's9_ng2': 'FeatureCounts', 's9_ng2s': '投入記録が存在しない',
  's9_ng3': 'CHAIN_HALTED', 's9_ng3s': '12:02:59 · 理由付き',
  's9_after': 'SLURM の afterany に任せていたら、2 段目は起動していた',
  's9_chips': [('再投入は 1 回だけ', 'SLURM 自身が一時的と報告したときのみ — OUT_OF_MEMORY / TIMEOUT / NODE_FAIL / PREEMPTED'),
               ('87 / 30 118', '10 日間で一時的失敗に当たった件数 = 0.29 %'),
               ('資源を上げて再投入', 'メモリ不足を同じ設定で出し直すのは確実な再失敗')],
  's9_src': '実測: 2026-09-11 fgcz-h-083 · 失敗判定は SLURM の終了状態そのもので、ログの読み取りではない',

  's10_title': '残っている穴は 2 つ。どちらも配管ではない',
  's10_fig': 'レシピ帳の貯め方と、まだ存在しない通知の経路。',
  's10_gapA': '残り 1 — レシピ帳がまだ空',
  's10_gapB': '残り 2 — 通知',
  's10_author': 'バイオインフォマティシャン', 's10_author2': '1 品ずつ手で書く。生成させない',
  's10_book': 'RecipeSkill-MCP-server', 's10_book2': 'レシピ帳 — ここに貯まっていく',
  's10_cards': ['NGS', 'Single Cell', 'Spatial', 'Long Read', 'ONT'],
  's10_chef': 'OMAKASE が献立を組む', 's10_chef2': 'その日の注文に合う一式を引く',
  's10_write': '書く', 's10_pull': '引く',
  's10_ev1': '献立ができた', 's10_ev2': '途中で止まった',
  's10_mail': 'メール', 's10_who': '人に届く', 's10_notyet': 'まだ無い',
  's10_chips': [('13 秒 – 1 229 秒', 'gStore コピー待ちの実測幅。こちらでは直せない'),
                ('デモは動く', '2 つの穴はどちらもデモ経路の外にある'),
                ('次の測定', 'ラベルが 30 件たまれば、提案精度の判定ができる')],
  's10_src': '実測: 2026-09-11 · 残り 2 つはいずれも実装量ではなく、領域知識と運用の決めごと',

  'axA_title': '付録 A — 構成要素',
  'axA_fig': '人の入力から計算クラスタまで。青は実測済み、灰の破線は未実装。',
  'axA_surface': '操作する場所', 'axA_ui': 'Web UI', 'axA_ui2': 'ポート 8770・鍵必須',
  'axA_cc': 'Claude Code', 'axA_cc2': 'MCP（標準入出力）',
  'axA_planned': '実装予定', 'axA_slack': 'Slack / Teams',
  'axA_h': 'hermes-agent', 'axA_h2': 'ハーネス 127.0.0.1:8642', 'axA_h3': '何をするか決める',
  'axA_llm': 'vLLM', 'axA_llm2': 'オンプレのモデル', 'axA_llm3': 'FGCZ の外に出ない',
  'axA_mcp': 'RecipeSkill-MCP-server', 'axA_mcp2': '100 個のツール', 'axA_mcp3': '知識と実行',
  'axA_api': 'Omakase-backend-API-server', 'axA_api2': 'REST API・18 アプリ', 'axA_api3': '083 ポート 3010',
  'axA_slurm': 'job_manager → SLURM', 'axA_slurm2': '既存の本番機構', 'axA_slurm3': '未変更',
  'axA_core': 'omakase-core', 'axA_core2': '普通の Python。タイマーと状態機械を持つ',
  'axA_note': ['判断するのはハーネスだけ。モデルは判断材料を、ツールサーバは実行能力を供給する。',
               'そして REST API が、実データと実ジョブに触れる唯一の扉である。'],
  'axA_src': '構成は 2026-09-09 のレポート図 1 と同じ。名称のみ本デッキの表記に置き換えてある',

  'sum_title': 'まとめ — 注文が入ってから、一皿が出るまで',
  'sum_fig': 'お任せの流れ。各段の下に、それを実際に担う部品を書いてある。',
  'sum_steps': [('注文が仕上がる', ['B-Fabric', 'status = processed']),
                ('板前が献立を組む', ['omakase-core', 'RecipeSkill-MCP-server']),
                ('献立をお見せする', ['提案 — アプリ・順序', 'そして選んだ理由']),
                ('お客がうなずく', ['人の承認', 'ここを越えるまで何も出ない']),
                ('厨房が順に仕上げる', ['Omakase-backend-API-server', 'job_manager → SLURM']),
                ('一皿ずつ出す', ['データセットと結果', '既存の画面にそのまま出る'])],
  'sum_note': 'タイマーと順番を持つのは板前（普通のコード）。モデルは献立を考えるが、順序は決めない。',
  'sum_catch': 'ルールが決め、AI が助け、人が出す',
  'sum_src': '構成は 2026-09-09 のレポート図 1 と同じ内容。名称と見せ方のみ本デッキの表記に置き換えてある',

  'axB_title': '付録 B — 5 つの独立した関門',
  'axB_fig': '5 つの関門。1 と 2 は入口を、3・4・5 は入った後にできることを守る。',
  'axB_gates': [('1. UI の鍵', '43 文字', '鍵が無ければ応答しない', '実測: 401'),
                ('2. ハーネスの鍵', '37 文字', 'ループバック限定', '実測: 401'),
                ('3. 接続先の登録', '書き込み可否を宣言', '鍵は名前で参照', '本番: 不可'),
                ('4. プロジェクト範囲', '鍵は 1 課題のみ', '範囲外は拒否', '実測: 403'),
                ('5. 書き込み方針', '読取専用 / 追加のみ', '1〜4 とは独立', 'API 自身が強制')],
  'axB_db1': 'fgcz-h-083 — テスト', 'axB_db1s': '専用 DB。19 課題。ここで全部走らせた',
  'axB_db2': 'fgcz-h-082 — 本番', 'axB_db2s': '2 608 課題・82 094 データセット。書き込みゼロ',
  'axB_note': '二重の拒否 — ハーネスに本番の鍵を渡しておらず、登録側でも書き込みを禁じている。',
  'axB_src': '実測: 2026-09-09 · 各関門は突破を試みて確認した',
 },

 'en': {
  # No CJK anywhere in the EN deck, including this link label — the format's
  # zero-leakage rule has no exception for navigation chrome.
  'lang': 'en', 'other': 'omakase_prototype_ja.html', 'other_label': 'Japanese version',
  'doctitle': 'OMAKASE System Prototype — 2026-09-16',
  'hint': '← → to move · R to replay · F for fullscreen',

  'cover_title': 'OMAKASE',
  'cover_sub': 'System prototype — from a finished order to a finished analysis',
  'cover_acro': 'Omics Metadata Automated Knowledge-based Analysis Suggestion &amp; Execution (name provisional)',
  'cover_catch': 'Rules decide, AI assists, humans release',
  'cover_meta': ['2026-09-16 · FGCZ Genomics',
                 'fgcz-h-083 (isolated test DB) · zero writes to production',
                 'Every number measured between 2026-09-09 and 09-11'],

  's2_title': 'Today, an order finishes and nothing happens',
  's2_fig': 'The situation today. Nothing reacts to the status change, and analyses are started by hand, one app at a time.',
  's2_a': 'A colleague', 's2_a_s': 'finishes the quality check',
  's2_b': 'B-Fabric', 's2_b_s': 'sets status to processed',
  's2_c': 'Nothing reacts', 's2_c_s': 'nobody is told',
  's2_row2': 'And the analysis itself is still started by hand, one app at a time',
  's2_app1': 'STAR', 's2_app2': 'FeatureCounts', 's2_app3': 'CountQC',
  's2_wait': 'a human waits, then starts the next one',
  's2_chips': [('1 463', 'sequencing orders in the last 12 months'),
               ('71 %', 'of 426 real analyses are 2+ steps deep = 304'),
               ('17 %', 'of 421 orders where history picks the right chain first')],
  's2_src': 'Measured 2026-08-20 (order count) and 2026-09-10 (chain depth, top-1). Read-only against the production DB.',

  's3_title': "OMAKASE composes a course from today's order, and proposes it",
  's3_fig': 'Six stages. A navy check runs live today, an orange cross does not exist yet.',
  's3_steps': [('Order done', 'detect'), ('Dataset', 'resolve'), ('Recipe', 'compose'),
               ('Human approves', 'the gate'), ('Run the course', 'parallel, halts'),
               ('Notify', 'deliver the result')],
  's3_done': [True, True, False, True, True, False],
  's3_note': 'It writes no apps. It picks the ones that exist and puts them in order — the reference genome is chosen inside the recipe.',
  's3_legend': [('navy = runs live', NAVY), ('orange = not built yet', ORANGE),
                ('thick = a human decides', GREY)],
  's3_catch': '— Rules decide, AI assists, humans release —',
  's3_src': 'Measured 2026-09-11 on fgcz-h-083 (isolated test DB). The two remaining stages are not implemented.',

  's4_title': 'It cannot miss — set subtraction, not change polling',
  's4_fig': 'Each tick asks for the whole set and subtracts what it has already handled. The difference is new work.',
  's4_setA': 'Everything B-Fabric', 's4_setA2': 'reports at status = processed',
  's4_setB': 'Everything OMAKASE', 's4_setB2': 'has already handled',
  's4_res': 'New orders', 's4_res2': 'the only ones it acts on',
  's4_minus': '−', 's4_eq': '=',
  's4_chips': [('0.6 – 2.1 s', 'one query for the whole set, over 4 runs'),
               ('30', 'orders ever set to processed in production'),
               ('0 missed', 'a day of downtime is caught up by the next tick')],
  's4_note': 'Being notified is the lossy option here. Drop one message and it is gone for good.',
  's4_src': 'Measured 2026-09-10, read-only against production B-Fabric. No statusmodifiedafter field exists, and no webhook.',

  's5_title': 'From order to data — 82 candidates down to one',
  's5_fig': 'How the dataset is found. When nothing qualifies it declines rather than guessing.',
  's5_f': [('All datasets in the project', '82'),
           ('carry the Order Id column', '62'),
           ('carry a single order_id', '3'),
           ('have no parent = raw data', '1')],
  's5_out': 'dataset 9', 's5_out2': 'the input to analyse',
  's5_dec': 'Nothing qualifies', 's5_dec2': 'DECLINED / exit code 3',
  's5_chips': [('7', 'detail calls made. Opening all 82 would have cost 82'),
               ('order 35773', 'set to processed by hand, really detected, and then declined'),
               ('order 35755', '→ dataset 9. This one goes through')],
  's5_src': 'Measured 2026-09-11. The link is not held by B-Fabric — it is derived inside Omakase-Platform.',

  's6_title': 'The reference genome is chosen inside the recipe, never typed in',
  's6_fig': 'How the reference is chosen. In four cases it cannot be, and then nothing is proposed.',
  's6_in': 'Species column of the dataset', 's6_in2': 'e.g. Mus musculus',
  's6_mid': '/srv/GT/reference-favorite', 's6_mid2': '5 species listed, exactly 1 build each',
  's6_out': 'The chosen reference', 's6_out2': 'the approver sees the real path',
  's6_path': 'Mus_musculus/GENCODE/GRCm39/…/Release_M37',
  's6_refuse': ['no Species', 'NA / blank', 'two species at once', 'species not curated'],
  's6_refuse_to': 'Propose nothing (in all four, that is the correct behaviour)',
  's6_chips': [('42 752 reads', 'assigned to genes, out of 100 000'),
               ('6 795 genes', 'ENSMUSG — mouse identifiers. The proof the choice was right'),
               ('Step 2 does not re-choose', 'STAR output carries Species and refBuild as columns')],
  's6_src': 'Measured 2026-09-11. The 2026-08-07 speed fixture put an Arabidopsis build on this same mouse data — not a precedent.',

  's7_title': 'Nothing is submitted until a human approves',
  's7_fig': 'What the proposal contains, and the three answers a human can give. No submission happens before that.',
  's7_card': 'Proposal', 's7_card_lines': ['which apps', 'in which order',
                                            'with which parameters', 'and why these'],
  's7_gate': 'Human approval',
  's7_ok': 'Accept', 's7_ok2': 'submitted as proposed',
  's7_edit': 'Edit', 's7_edit2': 'submitted as corrected',
  's7_no': 'Reject', 's7_no2': 'nothing is submitted',
  's7_chips': [('17 %', 'of 421 orders where history gets the chain right first — so it proposes, it does not act'),
               ('Three-valued', 'accepted / edited / rejected — scored by the human, never by the model'),
               ('No auto-approval', 'in the prototype a human approves explicitly, every time')],
  's7_src': 'Measured 2026-09-10 over 421 production orders. These verdicts are what the accuracy gate will later count.',

  's8_title': 'The chain runs in parallel — 6 min 31 s measured',
  's8_fig': 'Measured 2026-09-11, 15:49–15:55. The serial comparison is drawn on the same time axis.',
  's8_rows': ['FastQC', 'FastqScreen', 'STAR ×2', 'FeatureCounts ×2'],
  's8_done': 'DONE 6:31',
  's8_serial': 'Same work run one at a time: 12:13',
  's8_ann1': 'all three out within 41 s',
  's8_ann2': 'submitted 22 s after STAR reported COMPLETED, while FastQC still ran',
  's8_axis': 'min',
  's8_chips': [('6:31 / 12:13', 'measured in parallel / the same jobs summed serially'),
               ('3:25', 'the critical path, STAR → FeatureCounts'),
               ('5:28', 'the longest job is FastQC — and it is a leaf nobody waits for')],
  's8_src': 'Measured 2026-09-11 on fgcz-h-083. The 63 s between the last job and DONE is the poll interval.',

  's9_title': 'Halting is the feature — a failed step stops the chain',
  's9_fig': 'The happy path and a deliberately failed one. In the second, step 2 has no submission record at all.',
  's9_ok_lane': 'Happy path',
  's9_ng_lane': 'Deliberately failed',
  's9_ok1': 'STAR', 's9_ok1s': 'COMPLETED',
  's9_ok2': 'FeatureCounts', 's9_ok2s': 'submitted after step 1 completed',
  's9_ok3': 'DONE', 's9_ok3s': '11:59:39',
  's9_ng1': 'STAR', 's9_ng1s': 'FAILED — 30 s',
  's9_ng2': 'FeatureCounts', 's9_ng2s': 'no submission record exists',
  's9_ng3': 'CHAIN_HALTED', 's9_ng3s': '12:02:59 · with a reason',
  's9_after': "Left to SLURM's afterany, step 2 would have started anyway",
  's9_chips': [('One retry only', "and only when SLURM itself calls it transient — OUT_OF_MEMORY / TIMEOUT / NODE_FAIL / PREEMPTED"),
               ('87 / 30 118', 'jobs hit a transient end state in ten days = 0.29 %'),
               ('Retry asks for more', 'resubmitting an out-of-memory job unchanged just fails again')],
  's9_src': "Measured 2026-09-11 on fgcz-h-083. The decision reads SLURM's own end state, never a log file.",

  's10_title': 'Two gaps left, and neither of them is plumbing',
  's10_fig': 'How the recipe book fills up, and the notification path that does not exist yet.',
  's10_gapA': 'Gap 1 — the recipe book is still empty',
  's10_gapB': 'Gap 2 — notification',
  's10_author': 'A bioinformatician', 's10_author2': 'writes each by hand, never generated',
  's10_book': 'RecipeSkill-MCP-server', 's10_book2': 'the recipe book — they accumulate here',
  's10_cards': ['NGS', 'Single Cell', 'Spatial', 'Long Read', 'ONT'],
  's10_chef': 'OMAKASE composes the course', 's10_chef2': "it pulls the set today's order needs",
  's10_write': 'writes', 's10_pull': 'pulls',
  's10_ev1': 'a course is proposed', 's10_ev2': 'the course halted',
  's10_mail': 'e-mail', 's10_who': 'reaches a person', 's10_notyet': 'does not exist yet',
  's10_chips': [('13 s – 1 229 s', 'measured spread of the gStore copy queue. Not ours to fix'),
                ('The demo works', 'both gaps sit outside the demo path'),
                ('Next measurement', 'once 30 labels accumulate, proposal accuracy can be judged')],
  's10_src': 'Measured 2026-09-11. Neither gap is a question of engineering effort — they are domain knowledge and operations.',

  'axA_title': 'Appendix A — the components',
  'axA_fig': 'From a human request to the cluster. Navy is measured, grey dashed is not implemented.',
  'axA_surface': 'Control surfaces', 'axA_ui': 'Web UI', 'axA_ui2': 'port 8770, token required',
  'axA_cc': 'Claude Code', 'axA_cc2': 'MCP over stdio',
  'axA_planned': 'planned', 'axA_slack': 'Slack / Teams',
  'axA_h': 'hermes-agent', 'axA_h2': 'the harness, 127.0.0.1:8642', 'axA_h3': 'decides what to do',
  'axA_llm': 'vLLM', 'axA_llm2': 'on-premises model', 'axA_llm3': 'nothing leaves FGCZ',
  'axA_mcp': 'RecipeSkill-MCP-server', 'axA_mcp2': '100 tools', 'axA_mcp3': 'knowledge and actions',
  'axA_api': 'Omakase-backend-API-server', 'axA_api2': 'REST API, 18 apps', 'axA_api3': '083 port 3010',
  'axA_slurm': 'job_manager → SLURM', 'axA_slurm2': 'existing production machinery', 'axA_slurm3': 'unchanged',
  'axA_core': 'omakase-core', 'axA_core2': 'plain Python. It owns the timer and the state machine',
  'axA_note': ['The harness is the only component that decides anything. The model supplies judgement,',
               'the tool server supplies capability, and the REST API is the single door to real data and real jobs.'],
  'axA_src': 'Same architecture as figure 1 of the 2026-09-09 report. Only the component names are the ones used in this deck.',

  'sum_title': 'Summary — from the order coming in to the dish going out',
  'sum_fig': 'The omakase flow. Under each station is the component that actually does it.',
  'sum_steps': [('The order is ready', ['B-Fabric', 'status = processed']),
                ('Chef composes a course', ['omakase-core', 'RecipeSkill-MCP-server']),
                ('The course is shown', ['the proposal: apps,', 'order, and the reasons']),
                ('The guest nods', ['human approval', 'nothing leaves before it']),
                ('Kitchen cooks in order', ['Omakase-backend-API-server', 'job_manager → SLURM']),
                ('Served, dish by dish', ['datasets and results', 'in the existing UI'])],
  'sum_note': 'The chef owns the timer and the order of events, and the chef is plain code. The model helps compose; it never decides what happens when.',
  'sum_catch': 'Rules decide, AI assists, humans release',
  'sum_src': 'Same content as figure 1 of the 2026-09-09 report. Only the names and the framing are the ones used in this deck.',

  'axB_title': 'Appendix B — five independent gates',
  'axB_fig': 'Five gates. One and two guard the door; three, four and five guard what a caller may do once inside.',
  'axB_gates': [('1. UI token', '43 characters', 'no key, no answer', 'verified: 401'),
                ('2. Harness bearer', '37 characters', 'loopback only', 'verified: 401'),
                ('3. Target registry', 'declares may-it-write', 'tokens by name only', 'production: no'),
                ('4. Project scope', 'the token sees one project', 'anything else refused', 'verified: 403'),
                ('5. Write policy', 'read-only / add-only', 'independent of 1 to 4', 'enforced by the API')],
  'axB_db1': 'fgcz-h-083 — test', 'axB_db1s': 'its own DB, 19 projects. Everything ran here',
  'axB_db2': 'fgcz-h-082 — production', 'axB_db2s': '2 608 projects, 82 094 datasets. Zero writes',
  'axB_note': 'Refused twice over — the harness was given no production token, and the registry forbids writing anyway.',
  'axB_src': 'Measured 2026-09-09. Every gate was checked by trying to get past it.',
 },
}


# ----------------------------------------------------------------- figures ---
def fig_s2(t):
    g = []
    g.append(box(40, 24, 200, 84, t['s2_a'], t['s2_a_s'], d=0.05))
    g.append(arrow(248, 66, 300, 66, d=0.35))
    g.append(box(312, 24, 260, 84, t['s2_b'], t['s2_b_s'], d=0.45,
                 stroke=CYAN, fill='#f2fbff'))
    g.append(arrow(580, 66, 632, 66, d=0.75))
    g.append(box(644, 24, 300, 84, t['s2_c'], t['s2_c_s'], d=0.85,
                 stroke=GREY_L, dash='7 5', fill=WHITE, tcol=GREY, scol=GREY_L))
    g.append(f'<g class="an pulse" style="--d:1.2s"><circle cx="1010" cy="66" r="26" '
             f'fill="none" stroke="{ORANGE}" stroke-width="3"/>'
             f'<path d="M996 52 l28 28 M1024 52 l-28 28" stroke="{ORANGE}" '
             f'stroke-width="3" stroke-linecap="round" fill="none"/></g>')

    g.append(f'<g{anim("an", 1.35)}><path d="M40 148 L1140 148" stroke="#dfe4ea" '
             f'stroke-width="1.5" fill="none"/>' +
             txt(40, 178, t['s2_row2'], 15, GREY, weight='700') + '</g>')

    xs = [60, 420, 780]
    names = [t['s2_app1'], t['s2_app2'], t['s2_app3']]
    for i, (x, n) in enumerate(zip(xs, names)):
        g.append(box(x, 206, 220, 76, n, d=1.5 + i * 0.5, fill='#eef4f9'))
    for i in range(2):
        x1, x2 = xs[i] + 228, xs[i + 1] - 12
        # The person sits in the gap between two apps, clear of the row label above.
        g.append(person((x1 + x2) / 2, 224, d=1.75 + i * 0.5))
        g.append(arrow(x1, 256, x2, 256, d=1.8 + i * 0.5))
        g.append(f'<g{anim("an", 1.85 + i * 0.5)}>' +
                 txt((x1 + x2) / 2, 306, t['s2_wait'], 11.5, GREY, 'middle') + '</g>')
    g.append(dashed(1008, 256, 1120, 256, d=2.7))
    return svg(''.join(g), t['s2_fig'], 'f2')


def fig_s3(t):
    """Six stages. The genome is not one of them — choosing a reference is part of
    composing the recipe, so it lives on slide 6 and not in this chain."""
    g = []
    n = len(t['s3_steps'])
    w, gap = 172, 24
    x0 = (CANVAS_W - (n * w + (n - 1) * gap)) / 2
    human_at = 3
    for i, ((lab, sub), ok) in enumerate(zip(t['s3_steps'], t['s3_done'])):
        x = x0 + i * (w + gap)
        g.append(box(x, 96, w, 116,
                     lab, sub, d=0.15 + i * 0.16,
                     fill=WHITE if ok else '#fff7f0',
                     stroke=NAVY if ok else ORANGE, sw=3.5 if i == human_at else 2,
                     dash=None if ok else '7 5',
                     tfs=16, sfs=11,
                     tcol=NAVY if ok else ORANGE))
        g.append(tick(ok, x + w / 2, 70, d=0.25 + i * 0.16))
        if i < n - 1:
            g.append(arrow(x + w + 2, 154, x + w + gap - 4, 154,
                           color=NAVY if ok else ORANGE,
                           marker='arrNv' if ok else 'arr',
                           d=0.3 + i * 0.16, sw=2.2))
    g.append(f'<g{anim("an", 1.4)}>' +
             txt(CANVAS_W / 2, 264, t['s3_note'], 15, GREY, 'middle') + '</g>')
    lx = 190
    for i, (lab, col) in enumerate(t['s3_legend']):
        g.append(f'<g{anim("an", 1.6 + i * 0.12)}>'
                 f'<rect x="{lx:g}" y="296" width="16" height="16" rx="4" fill="{col}"/>' +
                 txt(lx + 24, 309, lab, 12.5, GREY) + '</g>')
        lx += 270
    g.append(f'<g{anim("an", 2.0)}>' +
             txt(CANVAS_W / 2, 356, t['s3_catch'], 16, ORANGE, 'middle', '700') + '</g>')
    return svg(''.join(g), t['s3_fig'], 'f3')


def fig_s10(t):
    """The two remaining gaps, as the things they actually are: a recipe book that
    fills up one hand-written recipe at a time, and a message nobody sends yet."""
    g = []
    # --- gap 1: the book fills up -----------------------------------------
    g.append(f'<g{anim("an", 0.05)}>' + txt(40, 26, t['s10_gapA'], 13, ORANGE, weight='700') + '</g>')
    g.append(box(40, 42, 240, 96, t['s10_author'], t['s10_author2'], d=0.15,
                 tfs=14, sfs=10.5))
    g.append(arrow(288, 90, 342, 90, d=0.4))
    g.append(f'<g{anim("an", 0.45)}>' + txt(315, 78, t['s10_write'], 11.5, ORANGE, 'middle') + '</g>')

    g.append(f'<g{anim("an", 0.55)}>' + rect(354, 34, 420, 112, fill='#fff7f0', stroke=ORANGE) +
             txt(564, 58, t['s10_book'], 15, ORANGE, 'middle', '700') +
             txt(564, 76, t['s10_book2'], 11, GREY, 'middle') + '</g>')
    cw, cg = 72, 8
    cx0 = 354 + (420 - (5 * cw + 4 * cg)) / 2
    for i, name in enumerate(t['s10_cards']):     # the book filling up, one card at a time
        x = cx0 + i * (cw + cg)
        g.append(f'<g{anim("an", 0.85 + i * 0.16)}>' +
                 rect(x, 90, cw, 40, fill=WHITE, stroke=ORANGE, sw=1.5, rx=6) +
                 txt(x + cw / 2, 115, name, 9.5, GREY, 'middle') + '</g>')

    g.append(arrow(782, 90, 836, 90, d=1.8))
    g.append(f'<g{anim("an", 1.85)}>' + txt(809, 78, t['s10_pull'], 11.5, ORANGE, 'middle') + '</g>')
    g.append(box(848, 42, 292, 96, t['s10_chef'], t['s10_chef2'], d=1.9,
                 stroke=NAVY, fill='#dbe7f0', tfs=15, sfs=10.5))

    # --- gap 2: nobody is told --------------------------------------------
    g.append(f'<g{anim("an", 2.05)}><path d="M40 178 L1140 178" stroke="#dfe4ea" '
             f'stroke-width="1.5" fill="none"/>' +
             txt(40, 210, t['s10_gapB'], 13, ORANGE, weight='700') + '</g>')
    g.append(box(40, 222, 240, 56, t['s10_ev1'], d=2.15, tfs=14))
    g.append(box(40, 292, 240, 56, t['s10_ev2'], d=2.25, tfs=14))
    g.append(dashed(288, 250, 424, 278, color=ORANGE, marker='arr', d=2.35))
    g.append(dashed(288, 320, 424, 292, color=ORANGE, marker='arr', d=2.4))
    g.append(box(436, 250, 220, 70, t['s10_mail'], d=2.45,
                 stroke=ORANGE, fill='#fff7f0', tcol=ORANGE, dash='7 5', tfs=16))
    g.append(dashed(664, 285, 716, 285, color=ORANGE, marker='arr', d=2.55))
    g.append(box(728, 250, 220, 70, t['s10_who'], d=2.6,
                 stroke=GREY_L, fill=WHITE, dash='7 5', tcol=GREY, tfs=16))
    g.append(f'<g class="an pulse" style="--d:2.7s">' +
             rect(968, 262, 172, 46, fill=ORANGE, stroke='none', sw=0, rx=8) +
             txt(1054, 291, t['s10_notyet'], 16, WHITE, 'middle', '700') + '</g>')
    return svg(''.join(g), t['s10_fig'], 'f10')


def fig_summary(t):
    """The same chain as the architecture, told as a counter in a restaurant.
    Each station carries the component that really does the work underneath it."""
    g = []
    n = len(t['sum_steps'])
    step = 190
    cx0 = 105
    g.append(f'<g{anim("an", 0.05)}>'
             f'<path d="M{cx0 - 46:g} 120 L{cx0 + (n - 1) * step + 46:g} 120" '
             f'stroke="#e7edf2" stroke-width="26" stroke-linecap="round" fill="none"/></g>')
    for i, (head, subs) in enumerate(t['sum_steps']):
        cx = cx0 + i * step
        gate = (i == 3)
        col = ORANGE if gate else NAVY
        g.append(f'<g{anim("an", 0.25 + i * 0.28)}>' +
                 txt(cx, 74, head, 14.5, col, 'middle', '700') +
                 f'<circle cx="{cx:g}" cy="120" r="26" fill="{col}"/>' +
                 txt(cx, 127, str(i + 1), 19, WHITE, 'middle', '700') + '</g>')
        for k, s in enumerate(subs):
            g.append(f'<g{anim("an", 0.4 + i * 0.28 + k * 0.06)}>' +
                     txt(cx, 176 + k * 17, s, 10.5, GREY, 'middle') + '</g>')
        if i < n - 1:
            g.append(arrow(cx + 32, 120, cx + step - 34, 120,
                           color=CYAN, marker='arrCy', d=0.5 + i * 0.28, sw=2.2))
    g.append(f'<g{anim("an", 2.3)}>' +
             txt(CANVAS_W / 2, 268, t['sum_note'], 14.5, GREY, 'middle') + '</g>')
    return svg(''.join(g), t['sum_fig'], 'fS')


def _dotgrid(x, y, cols, rows, total, d0, color=CYAN, skip_last=False):
    out = []
    k = 0
    for r in range(rows):
        for c in range(cols):
            if k >= total:
                break
            if skip_last and k == total - 1:
                k += 1
                continue
            out.append(f'<circle class="an" style="--d:{d0 + k * 0.012:g}s" '
                       f'cx="{x + c * 26:g}" cy="{y + r * 26:g}" r="7" fill="{color}"/>')
            k += 1
    return ''.join(out)


def fig_s4(t):
    g = []
    g.append(f'<g{anim("an", 0.1)}>' + rect(40, 60, 330, 232, fill='#f2fbff', stroke=CYAN) +
             txt(205, 88, t['s4_setA'], 14, NAVY, 'middle', '700') +
             txt(205, 108, t['s4_setA2'], 12, GREY, 'middle') + '</g>')
    g.append(_dotgrid(72, 146, 10, 3, 30, 0.5))

    g.append(f'<g{anim("an", 1.1)}>' + txt(400, 186, t['s4_minus'], 40, ORANGE, 'middle', '700') + '</g>')

    g.append(f'<g{anim("an", 1.2)}>' + rect(432, 60, 330, 232, fill=PANEL, stroke=GREY_L) +
             txt(597, 88, t['s4_setB'], 14, NAVY, 'middle', '700') +
             txt(597, 108, t['s4_setB2'], 12, GREY, 'middle') + '</g>')
    g.append(_dotgrid(464, 146, 10, 3, 30, 1.4, color=GREY_L, skip_last=True))

    g.append(f'<g{anim("an", 2.0)}>' + txt(792, 186, t['s4_eq'], 34, ORANGE, 'middle', '700') + '</g>')

    g.append(box(824, 96, 316, 160, t['s4_res'], t['s4_res2'], d=2.1,
                 stroke=ORANGE, fill='#fff7f0', tcol=ORANGE, tfs=19, sfs=12.5))
    g.append(f'<g class="an pulse" style="--d:2.5s">'
             f'<circle cx="982" cy="214" r="12" fill="{ORANGE}"/></g>')
    g.append(f'<g{anim("an", 2.7)}>' + txt(CANVAS_W / 2, 340, t['s4_note'], 14.5, GREY, 'middle') + '</g>')
    return svg(''.join(g), t['s4_fig'], 'f4')


def fig_s5(t):
    g = []
    widths = [820, 640, 230, 130]
    y = 34
    for i, ((lab, num), bw) in enumerate(zip(t['s5_f'], widths)):
        g.append(f'<rect class="grow" style="--d:{0.15 + i * 0.35:g}s" x="40" y="{y:g}" '
                 f'width="{bw:g}" height="56" rx="8" fill="{"#eef4f9" if i else "#dbe7f0"}" '
                 f'stroke="{NAVY}" stroke-width="2"/>')
        g.append(f'<g{anim("an", 0.35 + i * 0.35)}>' +
                 txt(58, y + 34, lab, 14.5, NAVY, weight='700') +
                 txt(40 + bw + 18, y + 34, num, 20, ORANGE, weight='700') + '</g>')
        if i < 3:
            g.append(arrow(70, y + 58, 70, y + 74, color=NAVY, marker='arrNv',
                           d=0.5 + i * 0.35, sw=2))
        y += 78
    g.append(arrow(180, 346, 250, 346, d=1.6))
    g.append(box(262, 314, 260, 62, t['s5_out'], t['s5_out2'], d=1.7,
                 stroke=NAVY, fill='#dbe7f0', tfs=18, sfs=11.5))

    # The refusal branches off the end of the funnel, not out of empty space.
    g.append(f'<g{anim("an", 2.0)}>'
             f'<path d="M178 296 L700 296 L700 308" stroke="{ORANGE}" stroke-width="2.5" '
             f'stroke-dasharray="6 5" fill="none" marker-end="url(#arr)"/></g>')
    g.append(box(560, 314, 400, 62, t['s5_dec'], t['s5_dec2'], d=2.1,
                 stroke=ORANGE, fill='#fff7f0', tcol=ORANGE, tfs=16, sfs=11.5))
    return svg(''.join(g), t['s5_fig'], 'f5')


def fig_s6(t):
    g = []
    g.append(box(40, 30, 280, 88, t['s6_in'], t['s6_in2'], d=0.1, tfs=15))
    g.append(arrow(328, 74, 382, 74, d=0.4))
    g.append(box(394, 30, 330, 88, t['s6_mid'], t['s6_mid2'], d=0.5,
                 stroke=CYAN, fill='#f2fbff', tfs=14))
    g.append(arrow(732, 74, 786, 74, d=0.8))
    g.append(box(798, 30, 342, 88, t['s6_out'], t['s6_out2'], d=0.9,
                 stroke=NAVY, fill='#dbe7f0', tfs=15))
    g.append(f'<g{anim("an", 1.2)}>' +
             txt(969, 152, t['s6_path'], 12, NAVY, 'middle', mono=True) + '</g>')

    g.append(f'<g{anim("an", 1.5)}><path d="M40 196 L1140 196" stroke="#dfe4ea" '
             f'stroke-width="1.5" fill="none"/></g>')
    bw, gap = 250, 33
    for i, lab in enumerate(t['s6_refuse']):
        x = 40 + i * (bw + gap)
        g.append(box(x, 220, bw, 54, lab, d=1.6 + i * 0.18,
                     stroke=ORANGE, fill='#fff7f0', tcol=ORANGE, tfs=14, dash='6 4'))
        g.append(arrow(x + bw / 2, 276, x + bw / 2, 302, d=1.75 + i * 0.18, sw=2))
    g.append(box(40, 312, 1100, 54, t['s6_refuse_to'], d=2.5,
                 stroke=ORANGE, fill='#ffeee0', tcol=ORANGE, tfs=16))
    return svg(''.join(g), t['s6_fig'], 'f6')


def fig_s7(t):
    g = []
    g.append(f'<g{anim("an", 0.1)}>' + rect(40, 52, 300, 250, fill=WHITE, stroke=NAVY) +
             txt(190, 88, t['s7_card'], 18, NAVY, 'middle', '700') +
             f'<path d="M70 104 L310 104" stroke="#dfe4ea" stroke-width="1.5" fill="none"/>' +
             '</g>')
    for i, line in enumerate(t['s7_card_lines']):
        g.append(f'<g{anim("an", 0.45 + i * 0.18)}>'
                 f'<circle cx="78" cy="{134 + i * 42:g}" r="4.5" fill="{CYAN}"/>' +
                 txt(94, 139 + i * 42, line, 14, GREY) + '</g>')

    g.append(arrow(348, 176, 404, 176, d=1.25))
    g.append(f'<g{anim("an", 1.35)}>'
             f'<path d="M440 40 L440 316" stroke="{NAVY}" stroke-width="4" fill="none"/>' +
             '</g>')
    g.append(person(440, 176, d=1.5, scale=1.9))
    g.append(f'<g{anim("an", 1.6)}>' +
             txt(440, 344, t['s7_gate'], 15, NAVY, 'middle', '700') + '</g>')

    rows = [(t['s7_ok'], t['s7_ok2'], NAVY, '#dbe7f0', 52),
            (t['s7_edit'], t['s7_edit2'], CYAN, '#f2fbff', 146),
            (t['s7_no'], t['s7_no2'], GREY_L, WHITE, 240)]
    for i, (lab, sub, col, fill, y) in enumerate(rows):
        g.append(arrow(478, y + 39, 540, y + 39, color=col,
                       marker='arrNv' if i == 0 else ('arrCy' if i == 1 else 'arrGy'),
                       d=1.8 + i * 0.25, sw=2.2))
        g.append(box(552, y, 588, 78, lab, sub, d=1.9 + i * 0.25, stroke=col, fill=fill,
                     tcol=NAVY if i < 2 else GREY, tfs=17))
    return svg(''.join(g), t['s7_fig'], 'f7')


def fig_s8(t):
    g = []
    X0, PX = 150, 1.26          # x origin, pixels per second (0 .. 760 s)
    def X(sec):
        return X0 + sec * PX

    jobs = [(0, 328, NAVY), (20, 200, CYAN), (41, 116, NAVY), (211, 89, NAVY)]
    for i, ((start, dur, col), lab) in enumerate(zip(jobs, t['s8_rows'])):
        y = 46 + i * 44
        g.append(f'<g{anim("an", 0.1 + i * 0.2)}>' +
                 txt(138, y + 21, lab, 13.5, NAVY, 'end', '700') + '</g>')
        g.append(f'<path class="an" style="--d:{0.1 + i * 0.2:g}s" d="M{X0:g} {y + 14:g} '
                 f'L{X(760):g} {y + 14:g}" stroke="#eef1f4" stroke-width="16" fill="none"/>')
        g.append(bar(X(start), y, max(dur * PX, 6), 30, col, d=0.35 + i * 0.25))

    g.append(f'<g{anim("an", 1.5)}>'
             f'<path d="M{X(391):g} 30 L{X(391):g} 236" stroke="{ORANGE}" stroke-width="2.5" '
             f'stroke-dasharray="6 5" fill="none"/>' +
             txt(X(391) + 10, 42, t['s8_done'], 14, ORANGE, weight='700') + '</g>')

    g.append(f'<g{anim("an", 1.7)}>' +
             txt(X(41) + 8, 38, t['s8_ann1'], 12, GREY) + '</g>')
    g.append(f'<g{anim("an", 1.9)}>'
             f'<path d="M{X(211):g} 236 L{X(211):g} 252" stroke="{GREY}" stroke-width="1.5" '
             f'fill="none"/>' + txt(X(211) - 4, 268, t['s8_ann2'], 12, GREY) + '</g>')

    # The serial comparison sits on the same axis, labelled above its own bar —
    # to the left of x=150 there is no room for a label in either language.
    g.append(f'<g{anim("an", 2.1)}>' +
             txt(X0 + 2, 300, t['s8_serial'], 13, GREY, weight='700') + '</g>')
    g.append(bar(X0, 308, 733 * PX, 22, '#c9d2da', d=2.2))

    g.append(f'<g{anim("an", 2.4)}>'
             f'<path d="M{X0:g} 346 L{X(760):g} 346" stroke="{GREY_L}" stroke-width="1.5" '
             f'fill="none"/></g>')
    for m in range(0, 13, 2):
        sec = m * 60
        g.append(f'<g{anim("an", 2.45 + m * 0.02)}>'
                 f'<path d="M{X(sec):g} 346 L{X(sec):g} 353" stroke="{GREY_L}" '
                 f'stroke-width="1.5" fill="none"/>' +
                 txt(X(sec), 372, str(m), 11.5, GREY, 'middle') + '</g>')
    g.append(f'<g{anim("an", 2.7)}>' + txt(X(760) + 12, 372, t['s8_axis'], 11.5, GREY) + '</g>')
    return svg(''.join(g), t['s8_fig'], 'f8')


def fig_s9(t):
    g = []
    g.append(f'<g{anim("an", 0.05)}>' + txt(40, 44, t['s9_ok_lane'], 14, NAVY, weight='700') + '</g>')
    lane = [(t['s9_ok1'], t['s9_ok1s'], 60), (t['s9_ok2'], t['s9_ok2s'], 420),
            (t['s9_ok3'], t['s9_ok3s'], 780)]
    for i, (lab, sub, x) in enumerate(lane):
        g.append(box(x, 58, 300, 80, lab, sub, d=0.2 + i * 0.35, stroke=NAVY,
                     fill='#dbe7f0' if i == 2 else PANEL))
        if i < 2:
            g.append(arrow(x + 308, 98, x + 352, 98, color=NAVY, marker='arrNv',
                           d=0.4 + i * 0.35))

    g.append(f'<g{anim("an", 1.2)}><path d="M40 172 L1140 172" stroke="#dfe4ea" '
             f'stroke-width="1.5" fill="none"/></g>')
    g.append(f'<g{anim("an", 1.3)}>' + txt(40, 210, t['s9_ng_lane'], 14, RED, weight='700') + '</g>')

    g.append(box(60, 224, 300, 80, t['s9_ng1'], t['s9_ng1s'], d=1.45,
                 stroke=RED, fill='#fdf0ed', tcol=RED))
    g.append(f'<g class="an pulse" style="--d:1.8s">'
             f'<path d="M392 214 L392 314" stroke="{RED}" stroke-width="4" fill="none"/>'
             f'<path d="M378 250 l28 28 M406 250 l-28 28" stroke="{RED}" stroke-width="3.5" '
             f'stroke-linecap="round" fill="none"/></g>')
    g.append(box(420, 224, 300, 80, t['s9_ng2'], t['s9_ng2s'], d=2.0,
                 stroke=GREY_L, fill=WHITE, dash='7 5', tcol=GREY_L, scol=GREY_L))
    g.append(dashed(728, 264, 772, 264, d=2.2))
    g.append(box(780, 224, 300, 80, t['s9_ng3'], t['s9_ng3s'], d=2.3,
                 stroke=RED, fill='#fdf0ed', tcol=RED))
    g.append(f'<g{anim("an", 2.6)}>' + txt(CANVAS_W / 2, 352, t['s9_after'], 14.5, GREY, 'middle') + '</g>')
    return svg(''.join(g), t['s9_fig'], 'f9')


def fig_axA(t):
    """The component chain, hermes-agent at the centre. Same shape as figure 1 of
    the 2026-09-09 report; only the names changed."""
    g = []
    g.append(f'<g{anim("an", 0.05)}>' + txt(40, 34, t['axA_surface'], 12.5, GREY, weight='700') + '</g>')
    g.append(box(40, 46, 230, 70, t['axA_ui'], t['axA_ui2'], d=0.15, tfs=15))
    g.append(box(40, 126, 230, 70, t['axA_cc'], t['axA_cc2'], d=0.3, tfs=15))
    g.append(box(40, 206, 230, 62, t['axA_slack'], t['axA_planned'], d=0.45, tfs=15,
                 stroke=GREY_L, dash='7 5', tcol=GREY_L, scol=GREY_L, fill=WHITE))

    g.append(arrow(278, 81, 324, 110, d=0.7))
    g.append(arrow(278, 161, 324, 132, d=0.8))
    g.append(dashed(278, 237, 324, 150, d=0.9))

    g.append(box(336, 74, 250, 96, t['axA_h'], t['axA_h2'], t['axA_h3'], d=1.0,
                 stroke=NAVY, sw=3, fill='#dbe7f0', tfs=16))
    g.append(box(336, 200, 250, 86, t['axA_core'], t['axA_core2'], d=1.15,
                 stroke=NAVY, sw=3, fill='#dbe7f0', tfs=16, sfs=10.5))

    g.append(arrow(594, 104, 640, 104, d=1.35))
    g.append(box(652, 34, 250, 82, t['axA_llm'], t['axA_llm2'], t['axA_llm3'], d=1.45,
                 stroke=CYAN, fill='#f2fbff', tfs=15))
    g.append(arrow(594, 140, 640, 168, d=1.55))
    g.append(box(652, 132, 250, 86, t['axA_mcp'], t['axA_mcp2'], t['axA_mcp3'], d=1.65,
                 stroke=NAVY, fill=PANEL, tfs=14))
    g.append(arrow(594, 240, 640, 262, d=1.75))
    g.append(box(652, 234, 250, 86, t['axA_api'], t['axA_api2'], t['axA_api3'], d=1.85,
                 stroke=NAVY, fill=PANEL, tfs=13.5))
    # The tool server reaches the cluster through the API, never around it, and the
    # API is what job_manager picks up from. Arrow direction is the claim here.
    g.append(arrow(777, 220, 777, 232, d=1.95, sw=2.2))
    g.append(arrow(910, 277, 942, 277, d=2.05))
    g.append(box(950, 234, 190, 86, t['axA_slurm'], t['axA_slurm2'], t['axA_slurm3'], d=2.15,
                 stroke=GREY, fill=WHITE, tfs=13, tcol=GREY))
    for k, line in enumerate(t['axA_note']):
        g.append(f'<g{anim("an", 2.3 + k * 0.08)}>' +
                 txt(CANVAS_W / 2, 342 + k * 20, line, 13, GREY, 'middle') + '</g>')
    return svg(''.join(g), t['axA_fig'], 'fA')


def fig_axB(t):
    g = []
    bw, gap = 212, 20          # 5*212 + 4*20 + 2*20 margin = 1180 exactly
    for i, (a, b, c, dd) in enumerate(t['axB_gates']):
        x = 20 + i * (bw + gap)
        col = NAVY if i < 2 else CYAN
        g.append(f'<g{anim("an", 0.1 + i * 0.2)}>' +
                 rect(x, 30, bw, 150, fill=WHITE, stroke=col) +
                 txt(x + bw / 2, 62, a, 15, NAVY, 'middle', '700') +
                 txt(x + bw / 2, 90, b, 11.5, GREY, 'middle') +
                 txt(x + bw / 2, 110, c, 11.5, GREY, 'middle') +
                 rect(x + 22, 128, bw - 44, 32, fill='#dbe7f0', stroke='none', sw=0, rx=8) +
                 txt(x + bw / 2, 149, dd, 12.5, NAVY, 'middle', '700') + '</g>')
    g.append(box(20, 212, 560, 86, t['axB_db1'], t['axB_db1s'], d=1.3,
                 stroke=NAVY, fill='#dbe7f0', tfs=16))
    g.append(box(600, 212, 560, 86, t['axB_db2'], t['axB_db2s'], d=1.5,
                 stroke=GREY_L, fill=WHITE, dash='7 5', tcol=GREY, scol=GREY))
    g.append(f'<g{anim("an", 1.8)}>' + txt(CANVAS_W / 2, 344, t['axB_note'], 14.5, GREY, 'middle') + '</g>')
    return svg(''.join(g), t['axB_fig'], 'fB')


# ------------------------------------------------------------------ slides ---
def chips(items, d0=0.2):
    out = []
    for i, (big, small) in enumerate(items):
        out.append(f'<div class="chip an" style="--d:{d0 + i * 0.14:g}s">'
                   f'<div class="chip-n">{esc(big)}</div>'
                   f'<div class="chip-s">{esc(small)}</div></div>')
    return '<div class="chip-row">' + ''.join(out) + '</div>'


def slide(n, total, title, figure, chip_html='', src='', foot=None):
    footer = foot if foot is not None else f'{n} / {total}'
    return (f'<div class="slide" data-slide="{n}">'
            f'<div class="slide-content">'
            f'<div class="slide-title an" style="--d:0s">{esc(title)}</div>'
            f'<div class="figwrap">{figure}</div>'
            f'{chip_html}'
            f'<div class="srcnote an" style="--d:1.1s">{esc(src)}</div>'
            f'</div>'
            f'<div class="slide-footer"><span class="fgcz-id">FGCZ · GENOMICS</span>'
            f'<span>{esc(footer)}</span></div></div>')


def build(lang: str, photo_uri: str) -> str:
    t = TX[lang]
    TOTAL = 11
    s = []

    # --- S1 cover -----------------------------------------------------------
    meta = ''.join(f'<div class="an" style="--d:{1.1 + i * 0.15:g}s">{esc(m)}</div>'
                   for i, m in enumerate(t['cover_meta']))
    s.append(
        f'<div class="slide title-slide active" data-slide="1">'
        f'<div class="cover-img omakase-photo" role="img" '
        f'aria-label="{esc(t["cover_sub"])}"></div>'
        f'<div class="cover-veil"></div>'
        f'<div class="cover-text">'
        f'<div class="cover-title an" style="--d:0.25s">{t["cover_title"]}</div>'
        f'<div class="cover-acro an" style="--d:0.45s">{t["cover_acro"]}</div>'
        f'<div class="cover-sub an" style="--d:0.65s">{esc(t["cover_sub"])}</div>'
        f'<div class="cover-catch an" style="--d:0.9s">— {esc(t["cover_catch"])} —</div>'
        f'<div class="cover-meta">{meta}</div>'
        f'</div></div>')

    s.append(slide(2, TOTAL, t['s2_title'], fig_s2(t), chips(t['s2_chips'], 2.9), t['s2_src']))
    s.append(slide(3, TOTAL, t['s3_title'], fig_s3(t), '', t['s3_src']))
    s.append(slide(4, TOTAL, t['s4_title'], fig_s4(t), chips(t['s4_chips'], 2.9), t['s4_src']))
    s.append(slide(5, TOTAL, t['s5_title'], fig_s5(t), chips(t['s5_chips'], 2.3), t['s5_src']))
    s.append(slide(6, TOTAL, t['s6_title'], fig_s6(t), chips(t['s6_chips'], 2.7), t['s6_src']))
    s.append(slide(7, TOTAL, t['s7_title'], fig_s7(t), chips(t['s7_chips'], 2.5), t['s7_src']))
    s.append(slide(8, TOTAL, t['s8_title'], fig_s8(t), chips(t['s8_chips'], 2.8), t['s8_src']))
    s.append(slide(9, TOTAL, t['s9_title'], fig_s9(t), chips(t['s9_chips'], 2.8), t['s9_src']))
    s.append(slide(10, TOTAL, t['s10_title'], fig_s10(t), chips(t['s10_chips'], 2.9), t['s10_src']))

    # Slide 11 is the close, not an appendix: the same chain as the architecture,
    # told as a counter in a restaurant, over a washed-out copy of the cover.
    s.append(f'<div class="slide summary-slide" data-slide="11">'
             f'<div class="wm omakase-photo" aria-hidden="true"></div>'
             f'<div class="wm-veil"></div>'
             f'<div class="slide-content">'
             f'<div class="slide-title an" style="--d:0s">{esc(t["sum_title"])}</div>'
             f'<div class="figwrap">{fig_summary(t)}</div>'
             f'<div class="closing an" style="--d:2.6s">{esc(t["sum_catch"])}</div>'
             f'<div class="srcnote an" style="--d:2.9s">{esc(t["sum_src"])}</div>'
             f'</div>'
             f'<div class="slide-footer"><span class="fgcz-id">FGCZ · GENOMICS</span>'
             f'<span>11 / 11</span></div></div>')

    s.append(slide(12, TOTAL, t['axA_title'], fig_axA(t), '', t['axA_src'], foot='Appendix A'))
    s.append(slide(13, TOTAL, t['axB_title'], fig_axB(t), '', t['axB_src'], foot='Appendix B'))

    return HTML.format(lang=t['lang'], doctitle=esc(t['doctitle']), css=CSS, js=JS,
                       defs=DEFS, slides=''.join(s), hint=esc(t['hint']), photo=photo_uri,
                       other=t['other'], other_label=esc(t['other_label']))


# -------------------------------------------------------------------- shell --
DEFS = (
    '<svg width="0" height="0" aria-hidden="true" focusable="false"><defs>'
    f'<marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" '
    f'markerHeight="6.5" orient="auto-start-reverse">'
    f'<path d="M0 0 L10 5 L0 10 z" fill="{ORANGE}"/></marker>'
    f'<marker id="arrNv" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" '
    f'markerHeight="6.5" orient="auto-start-reverse">'
    f'<path d="M0 0 L10 5 L0 10 z" fill="{NAVY}"/></marker>'
    f'<marker id="arrCy" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" '
    f'markerHeight="6.5" orient="auto-start-reverse">'
    f'<path d="M0 0 L10 5 L0 10 z" fill="{CYAN}"/></marker>'
    f'<marker id="arrGy" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" '
    f'markerHeight="6.5" orient="auto-start-reverse">'
    f'<path d="M0 0 L10 5 L0 10 z" fill="{GREY_L}"/></marker>'
    '</defs></svg>')

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:#06101c}
body{font-family:'Noto Sans JP','Hiragino Sans','Yu Gothic',Meiryo,Arial,Verdana,
     Helvetica,sans-serif;color:#003c68;-webkit-font-smoothing:antialiased}
.deck{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
.stage{width:1280px;height:720px;position:relative;transform-origin:center center;
       box-shadow:0 30px 80px rgba(0,0,0,.55);border-radius:4px;overflow:hidden}
.slide{position:absolute;inset:0;background:#fff;display:none}
.slide.active{display:block}
.slide-content{position:absolute;inset:0;padding:44px 50px 0 50px}
.slide-title{font-size:29px;font-weight:700;line-height:1.28;color:#003c68;
             letter-spacing:.2px;margin-bottom:10px}
.figwrap{width:1180px;height:380px}
.fig{width:1180px;height:380px;display:block}
.chip-row{display:flex;gap:16px;margin-top:14px}
.chip{flex:1;background:#f5f7fa;border-left:4px solid #0099cc;border-radius:6px;
      padding:10px 14px}
.chip-n{font-size:20px;font-weight:700;color:#003c68;line-height:1.15}
.chip-s{font-size:11.5px;color:#545e69;margin-top:4px;line-height:1.4}
.srcnote{position:absolute;left:50px;right:50px;bottom:44px;font-size:11px;
         color:#9aa5b1;line-height:1.45}
.closing{margin-top:16px;font-size:21px;font-weight:700;font-style:italic;
         color:#ea6b13;text-align:center}
.slide-footer{position:absolute;left:50px;right:50px;bottom:16px;display:flex;
              justify-content:space-between;font-size:11px;color:#9aa5b1;
              border-top:1px solid #e6eaee;padding-top:8px;letter-spacing:.6px}
.fgcz-id{font-weight:700;color:#003c68}

/* ---- the photograph, embedded once and used twice (cover + watermark) ---- */
.omakase-photo{background-image:var(--photo);background-size:cover;
               background-position:center}

/* ---- cover ---- */
.title-slide{background:#001428;overflow:hidden}
.cover-img{position:absolute;inset:0}
.slide.active .cover-img{animation:kenburns 22s ease-out both}
@keyframes kenburns{from{transform:scale(1.08)}to{transform:scale(1)}}
.cover-veil{position:absolute;inset:0;
  background:linear-gradient(100deg,rgba(0,20,40,.94) 0%,rgba(0,20,40,.86) 38%,
             rgba(0,20,40,.34) 62%,rgba(0,20,40,.12) 100%)}
.cover-text{position:absolute;left:64px;top:0;bottom:0;width:660px;display:flex;
            flex-direction:column;justify-content:center;color:#fff}
.cover-title{font-size:82px;font-weight:700;letter-spacing:10px;line-height:1;
             color:#fff}
.cover-acro{font-size:12.5px;color:#4dc9f6;margin-top:14px;letter-spacing:.3px}
.cover-sub{font-size:21px;margin-top:20px;line-height:1.5;color:#e8eef4}
.cover-catch{font-size:19px;font-style:italic;color:#ea6b13;margin-top:26px;
             font-weight:700}
.cover-meta{margin-top:34px;font-size:12.5px;color:#9fb4c6;line-height:1.9}

/* ---- summary: the same photograph, washed out behind the flow ---- */
.summary-slide{background:#fff;overflow:hidden}
.wm{position:absolute;inset:0;opacity:.20;filter:saturate(.75)}
.slide.active .wm{animation:kenburns 26s ease-out both}
.wm-veil{position:absolute;inset:0;
  background:linear-gradient(180deg,rgba(255,255,255,.90) 0%,rgba(255,255,255,.80) 45%,
             rgba(255,255,255,.92) 100%)}
.summary-slide .slide-content{position:relative}
.summary-slide .closing{margin-top:4px}

/* ---- animation ---- */
.an{opacity:0}
.slide.active .an{animation:rise .5s cubic-bezier(.22,.8,.3,1) both;
                  animation-delay:var(--d,0s)}
@keyframes rise{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
.draw{stroke-dasharray:1;stroke-dashoffset:1}
.slide.active .draw{animation:drawin .55s ease both;animation-delay:var(--d,0s)}
@keyframes drawin{to{stroke-dashoffset:0}}
.grow{transform-box:fill-box;transform-origin:left center;transform:scaleX(0)}
.slide.active .grow{animation:growx .65s cubic-bezier(.22,.8,.3,1) both;
                    animation-delay:var(--d,0s)}
@keyframes growx{to{transform:scaleX(1)}}
.slide.active .pulse{animation:rise .5s cubic-bezier(.22,.8,.3,1) both,
                     breathe 1.9s ease-in-out infinite;
                     animation-delay:var(--d,0s),calc(var(--d,0s) + .6s)}
@keyframes breathe{0%,100%{opacity:1}50%{opacity:.32}}

/* ---- hud ---- */
.hud{position:fixed;right:18px;bottom:14px;display:flex;align-items:center;gap:10px;
     font-size:12px;color:#7b8a99;z-index:20}
.hud button{background:rgba(255,255,255,.1);color:#cfe0ee;border:1px solid #35506b;
            border-radius:6px;width:30px;height:26px;cursor:pointer;font-size:13px}
.hud button:hover{background:rgba(255,255,255,.22)}
.hud .count{min-width:56px;text-align:center;color:#cfe0ee}
.hud a{color:#7b8a99;text-decoration:none;border-bottom:1px dotted #55687a}
.hint{position:fixed;left:18px;bottom:16px;font-size:11.5px;color:#5d6f80;z-index:20}

@media print{
  html,body{overflow:visible;background:#fff;height:auto}
  .deck{position:static;display:block}
  .stage{transform:none!important;width:1280px;height:auto;box-shadow:none}
  .slide{display:block!important;position:relative;width:1280px;height:720px;
         page-break-after:always;break-after:page}
  .an,.draw,.grow,.cover-img{opacity:1!important;animation:none!important;
         stroke-dashoffset:0!important;transform:none!important}
  .hud,.hint{display:none}
}
"""

JS = """
(function(){
  var slides=[].slice.call(document.querySelectorAll('.slide'));
  var stage=document.getElementById('stage');
  var count=document.getElementById('count');
  var i=0;
  function show(n){
    i=Math.max(0,Math.min(slides.length-1,n));
    slides.forEach(function(s,k){s.classList.toggle('active',k===i);});
    count.textContent=(i+1)+' / '+slides.length;
    if(history.replaceState){history.replaceState(null,'','#s'+(i+1));}
  }
  function replay(){
    var s=slides[i];s.classList.remove('active');void s.offsetWidth;s.classList.add('active');
  }
  function fit(){
    var k=Math.min(window.innerWidth/1280,window.innerHeight/720);
    stage.style.transform='scale('+k+')';
  }
  window.addEventListener('resize',fit);
  document.addEventListener('keydown',function(e){
    var k=e.key;
    if(k==='ArrowRight'||k===' '||k==='PageDown'||k==='n'){show(i+1);e.preventDefault();}
    else if(k==='ArrowLeft'||k==='PageUp'||k==='p'){show(i-1);e.preventDefault();}
    else if(k==='Home'){show(0);}
    else if(k==='End'){show(slides.length-1);}
    else if(k==='r'||k==='R'){replay();}
    else if(k==='f'||k==='F'){
      if(document.fullscreenElement){document.exitFullscreen();}
      else if(document.documentElement.requestFullscreen){
        document.documentElement.requestFullscreen();}
    }
  });
  document.getElementById('prev').addEventListener('click',function(){show(i-1);});
  document.getElementById('next').addEventListener('click',function(){show(i+1);});
  document.getElementById('rep').addEventListener('click',replay);
  var m=/^#s(\\d+)$/.exec(location.hash||'');
  fit();show(m?parseInt(m[1],10)-1:0);
})();
"""

HTML = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{doctitle}</title>
<style>:root{{--photo:url("{photo}")}}{css}</style>
</head>
<body>
{defs}
<div class="deck"><div class="stage" id="stage">
{slides}
</div></div>
<div class="hint">{hint}</div>
<div class="hud">
  <a href="{other}">{other_label}</a>
  <button id="prev" title="prev">&#8249;</button>
  <span class="count" id="count">1 / 12</span>
  <button id="next" title="next">&#8250;</button>
  <button id="rep" title="replay">&#8635;</button>
</div>
<script>{js}</script>
</body>
</html>
"""


def cover_data_uri() -> str:
    """The same JPEG the report embeds. log/ is gitignored, the report is not."""
    src = open(REPORT, encoding='utf-8').read()
    m = re.search(r'data:image/jpeg;base64,[A-Za-z0-9+/=]+', src)
    if not m:
        sys.exit(f'no cover image found in {REPORT}')
    uri = m.group(0)
    base64.b64decode(uri.split(',', 1)[1])          # fail loudly if truncated
    return uri


def _svgs(src):
    return re.findall(r'<svg\b.*?</svg>', src, re.S)


def verify_shapes(path):
    """Boxes and circles must stay inside their own canvas.

    check.py already guards text overflow. It does not look at rectangles, and a
    box hanging off the edge is invisible from a script in every other way — there
    is no browser on these nodes to catch it by eye.
    """
    import xml.etree.ElementTree as ET
    ns = '{http://www.w3.org/2000/svg}'
    bad = []
    for n, block in enumerate(_svgs(open(path, encoding='utf-8').read())):
        root = ET.fromstring(block)
        vb = root.get('viewBox')
        if not vb:
            continue
        _, _, vw, vh = [float(v) for v in vb.split()]

        def out(x0, y0, x1, y1, what):
            if x0 < -1 or y0 < -1 or x1 > vw + 1 or y1 > vh + 1:
                bad.append(f'{path}: svg #{n} {what} ({x0:g},{y0:g})-({x1:g},{y1:g}) '
                           f'outside {vw:g}x{vh:g}')

        for el in root.iter():
            tag = el.tag.replace(ns, '')
            if tag == 'rect':
                x, y = float(el.get('x', 0)), float(el.get('y', 0))
                out(x, y, x + float(el.get('width', 0)), y + float(el.get('height', 0)), 'rect')
            elif tag == 'circle':
                cx, cy, r = (float(el.get(k, 0)) for k in ('cx', 'cy', 'r'))
                out(cx - r, cy - r, cx + r, cy + r, 'circle')
            elif tag == 'path':
                d = el.get('d', '')
                # Absolute straight segments only. Relative (lower-case) commands
                # carry deltas, not coordinates, and reading them as coordinates
                # produces nonsense; arcs and curves are skipped for the same reason.
                if re.search(r'[^MLHV0-9.,\s-]', d):
                    continue
                nums = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?', d)]
                xs, ys = nums[0::2], nums[1::2]
                if xs and ys:
                    out(min(xs), min(ys), max(xs), max(ys), 'path')
    return bad


def verify_parity(a, b):
    """JA and EN must differ only in words. Same geometry, same animation timing."""
    def skeleton(path):
        src = open(path, encoding='utf-8').read()
        out = []
        for block in _svgs(src):
            block = re.sub(r'(<text\b[^>]*>).*?(</text>)', r'\1\2', block, flags=re.S)
            block = re.sub(r'(<title\b[^>]*>).*?(</title>)', r'\1\2', block, flags=re.S)
            out.append(block)
        return out
    sa, sb = skeleton(a), skeleton(b)
    if len(sa) != len(sb):
        return [f'{len(sa)} figures in ja, {len(sb)} in en']
    return [f'figure #{i} geometry differs between ja and en'
            for i, (x, y) in enumerate(zip(sa, sb)) if x != y]


def main():
    uri = cover_data_uri()
    for lang in ('ja', 'en'):
        path = os.path.join(HERE, f'omakase_prototype_{lang}.html')
        html = build(lang, uri)          # one copy of the JPEG, cover + watermark
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(html)
        print(f'wrote {path}  ({len(html) / 1024:.0f} KB)')

    ja = os.path.join(HERE, 'omakase_prototype_ja.html')
    en = os.path.join(HERE, 'omakase_prototype_en.html')
    problems = verify_shapes(ja) + verify_shapes(en) + verify_parity(ja, en)

    # The EN deck must contain no CJK. This has leaked before.
    src = re.sub(r'data:image/[^"\')]+', '', open(en, encoding='utf-8').read())
    cjk = sorted(set(re.findall(r'[　-ヿ㐀-鿿＀-￯]', src)))
    if cjk:
        problems.append(f'CJK leaked into the EN deck: {"".join(cjk)}')

    # The code names stay in the report and out of the deck (decided 2026-09-12).
    for path in (ja, en):
        body = re.sub(r'data:image/[^"\')]+', '', open(path, encoding='utf-8').read())
        for word in ('SUSHI', 'Omics-Studio', 'Omics Studio', 'Omakase-MCP'):
            if re.search(word, body):
                problems.append(f'{path}: code name "{word}" must not appear in the deck')

    print(f'checks: {len(problems)} problem(s)')
    for p in problems:
        print(f'  ! {p}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
