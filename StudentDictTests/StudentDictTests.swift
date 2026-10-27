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

    @Test func bopomofoSplitterReturnsOnePartPerCharacter() {
        #expect(BopomofoSplitter.split(phonetic: "ㄓ ㄨ ㄥ", count: 3) == ["ㄓ", "ㄨ", "ㄥ"])
        #expect(BopomofoSplitter.split(phonetic: "ㄓ ㄨ", count: 3) == ["ㄓ", "ㄨ", ""])
        #expect(BopomofoSplitter.split(phonetic: "ㄓ ㄨ ㄥ ㄍ", count: 3) == ["ㄓ", "ㄨ", "ㄥ"])
    }

}
