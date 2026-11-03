import FichaCore
import Testing

struct TagsFieldTests {
    @Test("a Tags field splits on the comma each keyboard types: Latin, Arabic, Chinese or Japanese")
    func aTagsFieldSplitsOnEachKeyboardsComma() {
        #expect(CardContent.tags(inField: "historia,arte") == ["historia", "arte"])
        #expect(CardContent.tags(inField: "تاريخ،فن") == ["تاريخ", "فن"])
        #expect(CardContent.tags(inField: "历史，文学") == ["历史", "文学"])
        #expect(CardContent.tags(inField: "歴史、文学") == ["歴史", "文学"])
    }

    @Test("a card takes clean tags from a field that mixes commas, with full-width spaces and a comma at the end")
    func aCardTakesCleanTagsFromMixedCommas() throws {
        let content = try #require(
            CardContent(
                type: nil, front: "犬", back: "dog", tags: CardContent.tags(inField: "历史，　文学、美术, 音乐，"),
                source: nil))

        #expect(content.tags == ["历史", "文学", "美术", "音乐"])
    }

    @Test("a Tags field left as it started gives back its tags whole, with commas in their names")
    func aFieldLeftAsItStartedKeepsItsTagsWhole() {
        let tags = ["历史、文学", "derecho, política", "arte"]

        #expect(
            CardContent.tags(inField: "历史、文学, derecho, política, arte", startedWith: tags) == tags)
    }

    @Test("a Tags field the user changed splits on its commas, whatever it started with")
    func aFieldTheUserChangedSplits() {
        #expect(CardContent.tags(inField: "历史、文学,美术", startedWith: ["历史、文学"]) == ["历史", "文学", "美术"])
        #expect(CardContent.tags(inField: "", startedWith: ["历史、文学"]) == [])
    }
}
