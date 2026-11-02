//
//  StudentDictTests.swift
//  StudentDictTests
//
//  Created by 薛宜安 on 2025/12/19.
//

import Testing
@testable import StudentDict

struct StudentDictTests {

    @Test func definitionParserSplitsNumberedDefinitionsAndExamples() {
        let items = DefinitionParser.parse("1. 第一個意思。如：第一個例句。2. 第二個意思")

        #expect(items.count == 2)
        #expect(items[0].number == "1")
        #expect(items[0].text == "第一個意思。")
        #expect(items[0].example == "如：第一個例句。")
        #expect(items[1].number == "2")
        #expect(items[1].text == "第二個意思")
    }

    @Test func definitionParserKeepsUnnumberedText() {
        let items = DefinitionParser.parse("沒有編號的定義")

        #expect(items.count == 1)
        #expect(items[0].number == nil)
        #expect(items[0].text == "沒有編號的定義")
        #expect(items[0].example == nil)
    }

    @Test func quotedWordsFindsDictionaryTermsAndSkipsLongSentences() {
        let source = "參見「喇叭」條。如：「把橘子扒開來吃。」也作『芭蕉』。俗呼瘡痕曰：『疤』。"
        let words = MOEText.quotedWords(source)

        #expect(words.contains("喇叭"))
        #expect(words.contains("芭蕉"))
        #expect(words.contains("疤"))
        #expect(!words.contains { $0.contains("橘子") })
    }

    @Test func quotedWordsSplitsAListOfShortHeadwords() {
        #expect(MOEText.quotedWords("如：「士、農、工、商」。") == ["士", "農", "工", "商"])
    }

    @Test func crossReferenceIDReadsEveryEntryNumber() {
        #expect(MOEText.crossReferenceIDs("(二)ㄅㄚˋ bà（00026）(三)ㄅㄞˇ bǎi（00137）") == ["00026", "00137"])
    }

    @Test func bopomofoSplitterReturnsOnePartPerCharacter() {
        #expect(BopomofoSplitter.split(phonetic: "ㄓ ㄨ ㄥ", count: 3) == ["ㄓ", "ㄨ", "ㄥ"])
        #expect(BopomofoSplitter.split(phonetic: "ㄓ ㄨ", count: 3) == ["ㄓ", "ㄨ", ""])
        #expect(BopomofoSplitter.split(phonetic: "ㄓ ㄨ ㄥ ㄍ", count: 3) == ["ㄓ", "ㄨ", "ㄥ"])
    }

}
