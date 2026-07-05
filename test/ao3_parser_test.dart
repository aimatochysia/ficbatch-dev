import 'package:flutter_test/flutter_test.dart';
import 'package:ficbatch/services/ao3_service.dart';

const _workPageWithSeries = '''
<html><body>
<div class="wrapper">
  <dl class="work meta group">
    <dt class="series">Series:</dt>
    <dd class="series">
      <span class="series">
        <span class="position">Part <strong>2</strong> of <a href="/series/123456">The Long Road Home</a></span>
      </span>
    </dd>
    <dt class="stats">Stats:</dt>
    <dd class="stats">
      <dl class="stats">
        <dd class="published">2024-01-15</dd>
        <dd class="status">2024-06-02</dd>
        <dd class="words">52,317</dd>
        <dd class="chapters">12/12</dd>
        <dd class="kudos">1,204</dd>
      </dl>
    </dd>
  </dl>
  <h2 class="title heading">A Winter's Tale</h2>
  <h3 class="byline heading"><a rel="author" href="/users/someone">someone</a></h3>
  <dd class="fandom tags"><a class="tag" href="#">Some Fandom</a></dd>
</div>
</body></html>
''';

const _workPageNoSeries = '''
<html><body>
  <h2 class="title heading">Standalone</h2>
  <h3 class="byline heading"><a rel="author" href="/users/x">x</a></h3>
</body></html>
''';

void main() {
  final service = Ao3Service();

  test('parses series name, id and position from a work page', () {
    final meta = service.parseWorkMetadata(_workPageWithSeries);
    expect(meta['title'], 'A Winter\'s Tale');
    expect(meta['seriesName'], 'The Long Road Home');
    expect(meta['seriesId'], '123456');
    expect(meta['seriesPosition'], 2);
    expect(meta['wordsCount'], 52317);
    expect(meta['chaptersCount'], 12);
    expect(meta['updatedAt'], DateTime.parse('2024-06-02'));
  });

  test('works without a series parse with null series fields', () {
    final meta = service.parseWorkMetadata(_workPageNoSeries);
    expect(meta['title'], 'Standalone');
    expect(meta['seriesName'], isNull);
    expect(meta['seriesId'], isNull);
    expect(meta['seriesPosition'], isNull);
  });
}
