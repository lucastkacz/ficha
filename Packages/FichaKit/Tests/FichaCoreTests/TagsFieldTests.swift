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
}
