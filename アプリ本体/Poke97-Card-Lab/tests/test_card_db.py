from card_db import parse_detail


POKEMON = '''
<h1 class="Heading1 mt20">試験ポケモン</h1>
<div class="LeftBox"><img class="fit" src="/assets/x_P_TEST.jpg" alt="試験ポケモン">
<div class="subtext Text-fjalla"><img class="img-regulation" alt="M1">&nbsp;001&nbsp;/&nbsp;100&nbsp;<img src="/rarity/ic_rare_rr.gif"></div>
<div class="author"><a>Tester</a></div></div>
<div class="RightBox"><div class="RightBox-inner">
<div class="TopInfo"><div><span class="type">たね</span><span class="hp-num">250</span><span class="hp-type">タイプ</span><span class="icon-fire icon"></span></div></div>
<h2>特性</h2><h4>みつける</h4><p>山札を見る。</p>
<h2>ワザ</h2><h4><span class="icon-fire icon"></span>ばくはつ<span class="f_right Text-fjalla">240+</span></h4><p>条件なら追加ダメージ。</p>
<table><tr><th>弱点</th><th>抵抗力</th><th>にげる</th></tr><tr><td><span class="icon-water icon"></span>×2</td><td>--</td><td class="escape"><span class="icon-none icon"></span></td></tr></table>
</div></div><div class="clear"></div>
<li class="List_item"><a>試験パック</a></li>
'''


def test_parse_pokemon():
    card = parse_detail("1", POKEMON)
    assert card["name"] == "試験ポケモン"
    assert card["category"] == "ポケモン"
    assert card["stage"] == "たね"
    assert card["hp"] == 250
    assert card["pokemon_type"] == "fire"
    assert card["abilities"][0]["name"] == "みつける"
    assert card["attacks"][0]["base_damage"] == 240
    assert card["attacks"][0]["damage_modifier"] == "+"
    assert card["retreat"] == 1


def test_parse_tool():
    source = '''<h1 class="Heading1">試験どうぐ</h1><img class="fit" src="/x_T_TEST.jpg">
    <div class="RightBox"><div class="RightBox-inner"><h2>ポケモンのどうぐ</h2><p>240以上なら効果。</p>
    </div></div><div class="clear"></div>'''
    card = parse_detail("2", source)
    assert card["category"] == "トレーナーズ"
    assert card["subcategory"] == "ポケモンのどうぐ"
    assert "240以上" in card["body_text"]
