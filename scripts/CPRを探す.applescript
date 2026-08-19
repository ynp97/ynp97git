on run
    set groupIndexFile to "/Users/yoshiakinagumo/Documents/Obsidian Vault/scripts/cubase_cpr_group_index.txt"
    set modeResult to display dialog "名前を覚えていなくても、一覧を眺めて探せます。\n\n同じ系列の版違いは、ひとつにまとめて表示します。" buttons {"言葉で探す", "全部見る", "最近の50件"} default button "最近の50件" with title "CPRを探す"
    set modeName to button returned of modeResult

    if modeName is "最近の50件" then
        set recordText to do shell script "/usr/bin/head -n 50 " & quoted form of groupIndexFile
    else if modeName is "全部見る" then
        set recordText to do shell script "/bin/cat " & quoted form of groupIndexFile
    else
        set promptResult to display dialog "CPR名、曲名、または保存フォルダの一部を入力してください。" default answer "" buttons {"キャンセル", "検索"} default button "検索" with title "CPRを探す"
        set keyword to text returned of promptResult
        if keyword is "" then return
        try
            set recordText to do shell script "/usr/bin/grep -i -F -- " & quoted form of keyword & " " & quoted form of groupIndexFile & " | /usr/bin/head -n 200"
        on error
            set recordText to ""
        end try
    end if

    if recordText is "" then
        display alert "見つかりませんでした" message "別の短い言葉で試してください。"
        return
    end if

    set recordItems to paragraphs of recordText
    set groupNames to {}
    repeat with oneRecord in recordItems
        set recordParts to my splitRecord(oneRecord as text)
        set groupName to item 1 of recordParts
        if groupNames does not contain groupName then set end of groupNames to groupName
    end repeat

    set chosenGroupResult to choose from list groupNames with title "CPRを探す" with prompt "作品・系列を選んでください。" OK button name "版を見る" cancel button name "閉じる"
    if chosenGroupResult is false then return
    set chosenGroup to item 1 of chosenGroupResult

    set versionNames to {}
    set versionPaths to {}
    repeat with oneRecord in recordItems
        set recordParts to my splitRecord(oneRecord as text)
        if item 1 of recordParts is chosenGroup then
            set end of versionNames to item 2 of recordParts
            set end of versionPaths to item 3 of recordParts
        end if
    end repeat

    if (count versionNames) is 1 then
        set chosenPath to item 1 of versionPaths
    else
        set chosenVersionResult to choose from list versionNames with title chosenGroup with prompt "開くバージョンを選んでください。" OK button name "選択" cancel button name "戻る"
        if chosenVersionResult is false then return
        set chosenVersion to item 1 of chosenVersionResult
        set chosenPath to ""
        repeat with itemNumber from 1 to count versionNames
            if item itemNumber of versionNames is chosenVersion then
                set chosenPath to item itemNumber of versionPaths
                exit repeat
            end if
        end repeat
        if chosenPath is "" then return
    end if

    set actionResult to display dialog my fileNameFromPath(chosenPath) buttons {"キャンセル", "Finderで表示", "Cubaseで開く"} default button "Finderで表示" with title "CPRが見つかりました"
    set actionName to button returned of actionResult
    if actionName is "Finderで表示" then
        tell application "Finder"
            activate
            reveal POSIX file chosenPath
        end tell
    else if actionName is "Cubaseで開く" then
        do shell script "/usr/bin/open " & quoted form of chosenPath
    end if
end run

on splitRecord(recordText)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to "|||"
    set recordParts to text items of recordText
    set AppleScript's text item delimiters to oldDelimiters
    return recordParts
end splitRecord

on fileNameFromPath(projectPath)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to "/"
    set pathParts to text items of projectPath
    set AppleScript's text item delimiters to oldDelimiters
    return item -1 of pathParts
end fileNameFromPath
