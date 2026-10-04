import XCTest
@testable import Daily

final class EventImportTests: XCTestCase {
    private let lumaPage = """
    <html><head>
    <meta property="og:title" content="Founders &amp; Friends Rooftop" />
    <script type="application/ld+json">
    {"@context":"https://schema.org","@type":"SocialEvent","name":"Founders &amp; Friends Rooftop",
     "startDate":"2026-10-10T18:30:00.000-07:00","endDate":"2026-10-10T21:00:00.000-07:00",
     "description":"Drinks and demos.",
     "location":{"@type":"Place","name":"The Battery","address":{"@type":"PostalAddress",
       "streetAddress":"717 Battery St","addressLocality":"San Francisco","addressRegion":"CA"}},
     "organizer":[{"@type":"Organization","name":"SF Builders"}]}
    </script></head><body>Hi</body></html>
    """

    private let partifulPage = """
    <html><head><meta property="og:title" content="Kevin's Halloween Party"></head><body>
    <script id="__NEXT_DATA__" type="application/json">
    {"props":{"pageProps":{
      "a_related":[{"title":"Some Other Party","startDate":"2026-11-01T20:00:00Z"}],
      "event":{"title":"Kevin's Halloween Party","startDate":"2026-10-31T02:00:00.000Z","endDate":"2026-10-31T06:00:00.000Z",
               "description":"Costumes required","location":{"displayName":"Kevin's place"}}}}}
    </script></body></html>
    """

    func testReadsJSONLDEvent() throws {
        let link = "https://lu.ma/rooftop"
        let e = try XCTUnwrap(EventImporter.parse(html: lumaPage, link: link))
        XCTAssertEqual(e.title, "Founders & Friends Rooftop")
        XCTAssertEqual(e.start, ISO8601DateFormatter().date(from: "2026-10-11T01:30:00Z"))
        XCTAssertEqual(e.durationMinutes, 150)
        XCTAssertEqual(e.location, "The Battery, 717 Battery St, San Francisco, CA")
        XCTAssertEqual(e.host, "SF Builders")
        XCTAssertTrue(e.note.hasPrefix("Hosted by SF Builders"))
        XCTAssertEqual(e.sourceName, "Luma")
    }

    func testReadsEmbeddedAppDataAndPicksTheRightEvent() throws {
        let e = try XCTUnwrap(EventImporter.parse(html: partifulPage, link: "https://partiful.com/e/abc"))
        XCTAssertEqual(e.title, "Kevin's Halloween Party")
        XCTAssertEqual(e.start, ISO8601DateFormatter().date(from: "2026-10-31T02:00:00Z"))
        XCTAssertEqual(e.durationMinutes, 240)
        XCTAssertEqual(e.location, "Kevin's place")
        XCTAssertEqual(e.details, "Costumes required")
    }

    func testPageWithoutTimeHasNoStart() {
        let html = "<html><head><meta property='og:title' content='Mystery'></head><body>Soon</body></html>"
        XCTAssertNil(EventImporter.parse(html: html, link: "https://partiful.com/e/x")?.start)
        XCTAssertEqual(EventPageParser.metaTags(html: html)["og:title"], "Mystery")
    }

    func testDefaultLengthIsTwoHours() {
        let e = ImportedEvent(title: "x", start: Date(), end: nil, link: "")
        XCTAssertEqual(e.durationMinutes, 120)
    }

    func testDateFormats() {
        XCTAssertNotNil(EventPageParser.date("2026-10-10T19:00:00Z"))
        XCTAssertNotNil(EventPageParser.date("2026-10-10T19:00:00.123-07:00"))
        XCTAssertNotNil(EventPageParser.date("2026-10-10T19:00"))
        XCTAssertEqual(EventPageParser.date(1_791_000_000_000.0), Date(timeIntervalSince1970: 1_791_000_000))
        XCTAssertNil(EventPageParser.date("2026-10-10"))
        XCTAssertNil(EventPageParser.date(3.0))
    }

    func testPageTextDropsScripts() {
        let text = EventPageParser.pageText(html: "<p>Sat&nbsp;Oct 10</p><script>var x = 1</script><style>p{}</style><b>7 PM</b>")
        XCTAssertEqual(text, "Sat Oct 10 7 PM")
    }

    func testEntities() {
        XCTAssertEqual(EventPageParser.decodeEntities("Tom &amp; Jerry&#39;s &#x2014; fun"), "Tom & Jerry's — fun")
    }

    func testRecognizesInviteLinks() {
        XCTAssertTrue(EventImporter.isEventLink("https://partiful.com/e/abc123"))
        XCTAssertTrue(EventImporter.isEventLink("https://lu.ma/xyz"))
        XCTAssertTrue(EventImporter.isEventLink("https://luma.com/xyz"))
        XCTAssertTrue(EventImporter.isEventLink("https://www.eventbrite.com/e/thing-123"))
        XCTAssertFalse(EventImporter.isEventLink("https://www.instagram.com/reel/abc"))
        XCTAssertFalse(EventImporter.isEventLink(""))
    }

    func testFirstLinkInShareText() {
        XCTAssertEqual(EventImporter.firstLink(in: "You're invited to Kevin's party! https://partiful.com/e/abc"),
                       "https://partiful.com/e/abc")
        XCTAssertEqual(EventImporter.firstLink(in: " https://lu.ma/x "), "https://lu.ma/x")
        XCTAssertNil(EventImporter.firstLink(in: "no link here"))
    }

    func testCanonicalIgnoresTracking() {
        XCTAssertEqual(EventImporter.canonical("https://www.Partiful.com/e/abc/?c=xyz#top"), "https://partiful.com/e/abc")
        XCTAssertEqual(EventImporter.canonical("https://partiful.com/e/abc"), "https://partiful.com/e/abc")
    }

    func testAIPromptHasZoneAndPageTitle() {
        let p = EventImportAI.prompt(link: "https://partiful.com/e/abc", meta: ["og:title": "Game night"],
                                     text: "Sat 8pm at Sam's", timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertTrue(p.contains("Partiful"))
        XCTAssertTrue(p.contains("America/Los_Angeles"))
        XCTAssertTrue(p.contains("og:title: Game night"))
        XCTAssertTrue(p.contains("Sat 8pm at Sam's"))
    }
}
