//-----------------------------------------------------------------------------
// KORG nanoKEY Studio — Cubase MIDI Remote スクリプト
// ノブ8個をサーフェスとして登録し、2つのマッピングページを提供:
//   Page 1 "Quick Controls" : ノブ1-8 → トラッククイックコントロール QC1-8
//   Page 2 "Vol Pan Sends"  : ノブ1=音量, ノブ2=パン, ノブ3-8=センド1-6
// 鍵盤・パッドは通常のMIDI入力として使うため、ここでは登録しない。
//-----------------------------------------------------------------------------

// ★設定: ノブのCC番号。実機と合わないときはKORG KONTROL Editorで
//   実機側のCC番号を確認し、この配列を書き換える（左のノブから順に）。
var KNOB_CCS = [20, 21, 22, 23, 24, 25, 26, 27]
var MIDI_CHANNEL = 0 // 0 = MIDIチャンネル1

var midiremote_api = require('midiremote_api_v1')

var deviceDriver = midiremote_api.makeDeviceDriver('KORG', 'nanoKEY Studio', 'nagumo')

var midiInput = deviceDriver.mPorts.makeMidiInput()
var midiOutput = deviceDriver.mPorts.makeMidiOutput()

// USB接続時のポート名で自動検出
deviceDriver.makeDetectionUnit().detectPortPair(midiInput, midiOutput)
    .expectInputNameContains('nanoKEY Studio')
    .expectOutputNameContains('nanoKEY Studio')

//-----------------------------------------------------------------------------
// サーフェス（画面上の見た目とMIDIバインド）
//-----------------------------------------------------------------------------
var surface = deviceDriver.mSurface

var knobs = []
for (var i = 0; i < 8; ++i) {
    var knob = surface.makeKnob(i * 2, 0, 2, 2)
    knob.mSurfaceValue.mMidiBinding
        .setInputPort(midiInput)
        .bindToControlChange(MIDI_CHANNEL, KNOB_CCS[i])
    surface.makeLabelField(i * 2, 2, 2, 1).relateTo(knob)
    knobs.push(knob)
}

//-----------------------------------------------------------------------------
// Page 1: トラッククイックコントロール
//-----------------------------------------------------------------------------
var pageQC = deviceDriver.mMapping.makePage('Quick Controls')
for (var q = 0; q < 8; ++q) {
    pageQC.makeValueBinding(
        knobs[q].mSurfaceValue,
        pageQC.mHostAccess.mTrackSelection.mMixerChannel.mQuickControls.getByIndex(q)
    )
}

//-----------------------------------------------------------------------------
// Page 2: 選択トラックの音量・パン・センド
//-----------------------------------------------------------------------------
var pageMix = deviceDriver.mMapping.makePage('Vol Pan Sends')
var channel = pageMix.mHostAccess.mTrackSelection.mMixerChannel
pageMix.makeValueBinding(knobs[0].mSurfaceValue, channel.mValue.mVolume)
pageMix.makeValueBinding(knobs[1].mSurfaceValue, channel.mValue.mPan)
for (var s = 0; s < 6; ++s) {
    pageMix.makeValueBinding(knobs[s + 2].mSurfaceValue, channel.mSends.getByIndex(s).mLevel)
}
