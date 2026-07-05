import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class Ao3Service {
  final http.Client httpClient;

  Ao3Service({http.Client? client}) : httpClient = client ?? http.Client();

  /// A descriptive User-Agent. AO3 throttles/blocks unidentified clients, so
  /// every outbound request should identify itself.
  static const String userAgent =
      'Mozilla/5.0 (compatible; FicBatch/1.0; +https://github.com/aimatochysia/FicBatch)';

  /// Fetch and parse a work's metadata from its AO3 page.
  Future<Map<String, dynamic>> fetchWorkMetadata(String workIdOrUrl) async {
    final url = _normalizeWorkUrl(workIdOrUrl);
    final resp = await httpClient.get(
      Uri.parse(url),
      headers: const {'User-Agent': userAgent},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch work (HTTP ${resp.statusCode})');
    }
    return parseWorkMetadata(resp.body);
  }

  /// Parse a work page's HTML.
  ///
  /// Returns a map with: `title`, `author`, `tags` (`List<String>`), `summary`,
  /// `wordsCount`, `chaptersCount`, `kudosCount`, `hitsCount`,
  /// `commentsCount`, `publishedAt` (DateTime?), `updatedAt` (DateTime?),
  /// `seriesName`/`seriesId`/`seriesPosition` and the raw `rawHtml`. Missing
  /// fields are returned as `null` (or empty list).
  Map<String, dynamic> parseWorkMetadata(String body) {
    final doc = html_parser.parse(body);

    final title = (doc.querySelector('h2.title.heading') ??
                doc.querySelector('h2.title'))
            ?.text
            .trim() ??
        'Unknown title';

    // A work can have multiple authors.
    final authors = doc
        .querySelectorAll('a[rel="author"]')
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final author = authors.isEmpty ? 'Unknown author' : authors.join(', ');

    // Tag groups (rating, warnings, categories, fandoms, relationships,
    // characters, additional/freeform) are all rendered as `a.tag` inside
    // `dd.tags` blocks in the work meta sidebar.
    final tags = doc
        .querySelectorAll('dd.tags a.tag')
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final summary = (doc.querySelector('.summary .userstuff') ??
            doc.querySelector('blockquote.userstuff'))
        ?.text
        .trim();

    // Series: `dd.series span.position` renders "Part N of <a
    // href="/series/123">Name</a>". A work can belong to several series —
    // take the first. Queried in two steps: package:html's selector engine
    // doesn't match descendant selectors with a compound ancestor here.
    String? seriesName;
    String? seriesId;
    int? seriesPosition;
    final seriesDd = doc.querySelector('dd.series');
    final position = seriesDd?.querySelector('.position') ?? seriesDd;
    if (position != null) {
      for (final link in position.querySelectorAll('a')) {
        final match =
            RegExp(r'/series/(\d+)').firstMatch(link.attributes['href'] ?? '');
        if (match == null) continue;
        final name = link.text.trim();
        seriesName = name.isEmpty ? null : name;
        seriesId = match.group(1);
        seriesPosition = int.tryParse(
            RegExp(r'Part\s+(\d+)').firstMatch(position.text)?.group(1) ?? '');
        break;
      }
    }

    return {
      'title': title,
      'author': author,
      'tags': tags,
      'summary': (summary != null && summary.isNotEmpty) ? summary : null,
      'wordsCount': _parseInt(doc.querySelector('dd.words')),
      'chaptersCount': _parseChapters(doc.querySelector('dd.chapters')),
      'kudosCount': _parseInt(doc.querySelector('dd.kudos')),
      'hitsCount': _parseInt(doc.querySelector('dd.hits')),
      'commentsCount': _parseInt(doc.querySelector('dd.comments')),
      'publishedAt': _parseDate(doc.querySelector('dd.published')),
      'updatedAt': _parseDate(doc.querySelector('dd.status')) ??
          _parseDate(doc.querySelector('dd.published')),
      'seriesName': seriesName,
      'seriesId': seriesId,
      'seriesPosition': seriesPosition,
      'rawHtml': body,
    };
  }

  String cleanWorkHtml(String rawHtml) {
    final doc = html_parser.parse(rawHtml);

    doc
        .querySelectorAll('script, header, footer, nav')
        .forEach((e) => e.remove());

    doc
        .querySelectorAll('.header, .footer, .social, .admin-tools')
        .forEach((e) => e.remove());

    doc.querySelectorAll('img').forEach((img) {
      img.attributes['style'] = 'max-width:100%;height:auto;';
    });
    return doc.outerHtml;
  }

  /// Parse an integer out of a stats `dd` element, stripping grouping commas
  /// and any surrounding label text.
  int? _parseInt(dom.Element? el) {
    if (el == null) return null;
    final digits = el.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  /// Chapters are rendered like "5/12" or "5/?" — take the published count
  /// (the number before the slash).
  int? _parseChapters(dom.Element? el) {
    if (el == null) return null;
    final text = el.text.trim();
    final first = text.split('/').first.replaceAll(RegExp(r'[^0-9]'), '');
    if (first.isEmpty) return null;
    return int.tryParse(first);
  }

  /// AO3 renders published/updated dates as ISO `yyyy-MM-dd`.
  DateTime? _parseDate(dom.Element? el) {
    if (el == null) return null;
    final text = el.text.trim();
    if (text.isEmpty) return null;
    final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(text);
    return DateTime.tryParse(match?.group(0) ?? text);
  }

  String _normalizeWorkUrl(String input) {
    if (input.startsWith('http')) return input;
    if (input.startsWith('/works/')) return 'https://archiveofourown.org$input';
    return 'https://archiveofourown.org/works/$input';
  }
}
