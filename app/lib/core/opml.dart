import 'package:xml/xml.dart';

import 'library.dart';
import 'models.dart';

/// Subscriptions from an OPML file (AntennaPod's "OPML export", gPodder, any
/// podcast app). Outline folders become tags. Nothing is fetched here, so the
/// import works offline; call [Library.refreshAll] afterwards to load episodes.
/// Returns the number of podcasts found.
int importOpml(Library lib, String xml) {
  final doc = XmlDocument.parse(xml);
  final body = doc.findAllElements('body').firstOrNull;
  if (body == null) throw const FormatException('Not an OPML file');
  var count = 0;
  void walk(XmlElement parent, List<String> folders) {
    for (final o in parent.childElements.where(
      (e) => e.name.local == 'outline',
    )) {
      final url = o.getAttribute('xmlUrl') ?? o.getAttribute('xmlurl') ?? '';
      if (url.startsWith('http')) {
        final title = o.getAttribute('title') ?? o.getAttribute('text') ?? '';
        lib.importPodcast(
          Podcast(feedUrl: url, title: title, tags: [...folders]),
          const [],
        );
        count++;
      } else {
        final name = o.getAttribute('title') ?? o.getAttribute('text') ?? '';
        walk(o, name.isEmpty ? folders : [...folders, name]);
      }
    }
  }

  walk(body, const []);
  lib.finishImport();
  return count;
}

String buildOpml(List<Podcast> podcasts) {
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element(
    'opml',
    attributes: {'version': '2.0'},
    nest: () {
      b.element(
        'head',
        nest: () => b.element('title', nest: 'PodSync subscriptions'),
      );
      b.element(
        'body',
        nest: () {
          for (final p in podcasts) {
            b.element(
              'outline',
              attributes: {
                'type': 'rss',
                'text': p.displayTitle,
                'title': p.displayTitle,
                'xmlUrl': p.feedUrl,
              },
            );
          }
        },
      );
    },
  );
  return b.buildDocument().toXmlString(pretty: true);
}
