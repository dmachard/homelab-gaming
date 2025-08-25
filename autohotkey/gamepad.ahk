#Requires AutoHotkey v2.0
#Include XInput.ahk

global XINPUT_GAMEPAD_GUIDE := 0x0400

XInput_Init()

SetTimer(CheckGuide, 50)

CheckGuide(*) {
    state := XInput_GetState(0)
    if !(state is Object) {
        return
    }

    if (state.wButtons & XINPUT_GAMEPAD_BACK) && (state.wButtons & XINPUT_GAMEPAD_START) {
        Send("!{F4}")   ; Alt+F4
        Sleep 500       ; Attendre 500 ms
        Send("{Enter}") ; Envoyer Enter
        while (XInput_GetState(0) is Object && XInput_GetState(0).wButtons & XINPUT_GAMEPAD_GUIDE)
            Sleep 50
    }
}
