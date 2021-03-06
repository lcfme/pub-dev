// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:client_data/page_data.dart';
import 'package:meta/meta.dart';
import 'package:pana/pana.dart' show getRepositoryUrl;

import '../../analyzer/analyzer_client.dart';
import '../../package/models.dart';
import '../../scorecard/models.dart';
import '../../search/search_service.dart';
import '../../shared/email.dart' show EmailAddress;
import '../../shared/tags.dart';
import '../../shared/urls.dart' as urls;

import '../static_files.dart';

import '_cache.dart';
import '_utils.dart';
import 'detail_page.dart';
import 'layout.dart';
import 'misc.dart';
import 'package_analysis.dart';

String _renderLicenses(String baseUrl, List<LicenseFile> licenses) {
  if (licenses == null || licenses.isEmpty) return null;
  return licenses.map((license) {
    final String escapedName = htmlEscape.convert(license.shortFormatted);
    String html = escapedName;

    if (license.url != null && license.path != null) {
      final String escapedLink = htmlAttrEscape.convert(license.url);
      final String escapedPath = htmlEscape.convert(license.path);
      html += ' (<a href="$escapedLink">$escapedPath</a>)';
    } else if (license.path != null) {
      final String escapedPath = htmlEscape.convert(license.path);
      html += ' ($escapedPath)';
    }
    return html;
  }).join('<br/>');
}

String _renderDependencyList(AnalysisView analysis) {
  if (analysis == null ||
      !analysis.hasPanaSummary ||
      analysis.directDependencies == null) return null;
  final List<String> packages =
      analysis.directDependencies.map((pd) => pd.package).toList()..sort();
  if (packages.isEmpty) return null;
  return packages
      .map((p) => '<a href="${urls.pkgPageUrl(p)}">$p</a>')
      .join(', ');
}

String _renderInstallTab(PackageVersion selectedVersion, List<String> tags) {
  final packageName = selectedVersion.package;
  final isFlutterPackage = selectedVersion.pubspec.usesFlutter;
  List importExamples;
  if (selectedVersion.libraries.contains('$packageName.dart')) {
    importExamples = [
      {
        'package': packageName,
        'library': '$packageName.dart',
      },
    ];
  } else {
    importExamples = selectedVersion.libraries.map((library) {
      return {
        'package': selectedVersion.packageKey.id,
        'library': library,
      };
    }).toList();
  }

  final executables = selectedVersion.pubspec.executables?.keys?.toList();
  executables?.sort();
  final hasExecutables = executables != null && executables.isNotEmpty;

  final exampleVersionConstraint = '^${selectedVersion.version}';

  final bool usePubGet = !isFlutterPackage ||
      tags == null ||
      tags.isEmpty ||
      tags.contains(SdkTag.sdkDart);

  final bool useFlutterPackagesGet =
      isFlutterPackage || (tags != null && tags.contains(SdkTag.sdkFlutter));

  String editorSupportedToolHtml;
  if (usePubGet && useFlutterPackagesGet) {
    editorSupportedToolHtml =
        '<code>pub get</code> or <code>flutter pub get</code>';
  } else if (useFlutterPackagesGet) {
    editorSupportedToolHtml = '<code>flutter pub get</code>';
  } else {
    editorSupportedToolHtml = '<code>pub get</code>';
  }

  return templateCache.renderTemplate('pkg/install_tab', {
    'use_as_an_executable': hasExecutables,
    'use_as_a_library': !hasExecutables || importExamples.isNotEmpty,
    'package': packageName,
    'example_version_constraint': exampleVersionConstraint,
    'has_libraries': importExamples.isNotEmpty,
    'import_examples': importExamples,
    'use_pub_get': usePubGet,
    'use_flutter_packages_get': useFlutterPackagesGet,
    'show_editor_support': usePubGet || useFlutterPackagesGet,
    'editor_supported_tool_html': editorSupportedToolHtml,
    'executables': executables,
  });
}

/// Renders the right-side info box (quick summary of the package, mostly coming
/// from pubspec.yaml).
String renderPkgInfoBox(
  Package package,
  PackageVersion selectedVersion,
  List<String> uploaderEmails,
  AnalysisView analysis,
) {
  final packageLinks = selectedVersion.packageLinks;

  String documentationUrl = packageLinks.documentationUrl;
  if (urls.hideUserProvidedDocUrl(documentationUrl)) {
    documentationUrl = null;
  }
  final dartdocsUrl = urls.pkgDocUrl(
    package.name,
    version: selectedVersion.version,
    isLatest: selectedVersion.version == package.latestVersion,
  );

  final metaLinks = <Map<String, dynamic>>[];
  final docLinks = <Map<String, dynamic>>[];
  void addLink(
    String href,
    String label, {
    bool detectServiceProvider = false,
    bool documentation = false,
  }) {
    if (href == null || href.isEmpty) {
      return;
    }
    if (detectServiceProvider) {
      final providerName = urls.inferServiceProviderName(href);
      if (providerName != null) {
        label += ' ($providerName)';
      }
    }
    final linkData = <String, dynamic>{'href': href, 'label': label};
    if (documentation) {
      docLinks.add(linkData);
    } else {
      metaLinks.add(linkData);
    }
  }

  if (packageLinks.repositoryUrl != packageLinks.homepageUrl) {
    addLink(packageLinks.homepageUrl, 'Homepage');
  }
  addLink(packageLinks.repositoryUrl, 'Repository',
      detectServiceProvider: true);
  addLink(packageLinks.issueTrackerUrl, 'View/report issues');
  addLink(documentationUrl, 'Documentation', documentation: true);
  if (analysis.hasApiDocs) {
    addLink(dartdocsUrl, 'API reference', documentation: true);
  }

  return templateCache.renderTemplate('pkg/info_box', {
    'is_flutter_favorite':
        (package.assignedTags ?? []).contains(PackageTags.isFlutterFavorite),
    'name': package.name,
    'description': selectedVersion.pubspec.description,
    'meta_links': metaLinks,
    'has_doc_links': docLinks.isNotEmpty,
    'doc_links': docLinks,
    'publisher_id': package.publisherId,
    'publisher_link': package.publisherId == null
        ? null
        : urls.publisherUrl(package.publisherId),
    'uploaders_title': uploaderEmails.length > 1 ? 'Uploaders' : 'Uploader',
    'uploaders_html':
        uploaderEmails.isEmpty ? null : _getAuthorsHtml(uploaderEmails),
    'license_html': _renderLicenses(packageLinks.baseUrl, analysis?.licenses),
    'dependencies_html': _renderDependencyList(analysis),
    'search_deps_link': urls.searchUrl(q: 'dependency:${package.name}'),
    // TODO: remove the below keys after we've migrated to the new UI
    'all_links': [...metaLinks, ...docLinks],
  });
}

/// Renders the `views/pkg/header.mustache` template for header metadata and
/// wraps it with content-header.
String renderPkgHeader(Package package, PackageVersion selectedVersion,
    bool isLiked, AnalysisView analysis) {
  final bool showDevVersion = package.latestDevVersion != null &&
      package.latestSemanticVersion < package.latestDevSemanticVersion;
  final bool showUpdated =
      selectedVersion.version != package.latestVersion || showDevVersion;

  final metadataHtml = templateCache.renderTemplate('pkg/header', {
    'publisher_id': package.publisherId,
    'publisher_url': package.publisherId == null
        ? null
        : urls.publisherUrl(package.publisherId),
    'latest': {
      'show_updated': showUpdated,
      'show_dev_version': showDevVersion,
      'stable_url': urls.pkgPageUrl(package.name),
      'stable_version': package.latestVersion,
      'dev_url':
          urls.pkgPageUrl(package.name, version: package.latestDevVersion),
      'dev_version': package.latestDevVersion,
    },
    'short_created': selectedVersion.shortCreated,
  });
  final pkgView = PackageView.fromModel(
    package: package,
    version: selectedVersion,
    scoreCard: analysis?.card,
  );
  return renderDetailHeader(
    title: '${package.name} ${selectedVersion.version}',
    packageLikes: package.likes,
    isLiked: isLiked,
    isFlutterFavorite:
        (package.assignedTags ?? []).contains(PackageTags.isFlutterFavorite),
    metadataHtml: metadataHtml,
    tagsHtml: renderTags(
      package: pkgView,
      searchQuery: null,
      showTagBadges: true,
    ),
  );
}

/// Renders the `views/pkg/show.mustache` template.
String renderPkgShowPage(
  Package package,
  bool isLiked,
  List<String> uploaderEmails,
  PackageVersion selectedVersion,
  AnalysisView analysis, {
  @required bool isAdmin,
}) {
  final card = analysis?.card;

  final content = renderDetailPage(
    headerHtml: renderPkgHeader(package, selectedVersion, isLiked, analysis),
    tabs: _pkgTabs(package, selectedVersion, analysis, isAdmin),
    infoBoxLead: selectedVersion.ellipsizedDescription,
    infoBoxHtml:
        renderPkgInfoBox(package, selectedVersion, uploaderEmails, analysis),
    footerHtml: renderPackageSchemaOrgHtml(package, selectedVersion, analysis),
  );

  final isFlutterPackage = selectedVersion.pubspec.usesFlutter;
  final isVersionPage = package.latestVersion != selectedVersion.version;
  final packageAndVersion = isVersionPage
      ? '${selectedVersion.package} ${selectedVersion.version}'
      : selectedVersion.package;
  final pageTitle =
      '$packageAndVersion | ${isFlutterPackage ? 'Flutter' : 'Dart'} Package';
  final canonicalUrl =
      isVersionPage ? urls.pkgPageUrl(package.name, includeHost: true) : null;
  final noIndex = (card?.isSkipped ?? false) ||
      (card?.overallScore == 0.0) ||
      package.isDiscontinued;
  return renderLayoutPage(
    PageType.package,
    content,
    title: pageTitle,
    pageDescription: selectedVersion.ellipsizedDescription,
    faviconUrl: isFlutterPackage ? staticUrls.flutterLogo32x32 : null,
    canonicalUrl: canonicalUrl,
    noIndex: noIndex,
    pageData: pkgPageData(package, selectedVersion),
  );
}

PageData pkgPageData(Package package, PackageVersion selectedVersion) {
  return PageData(
    pkgData: PkgData(
        package: package.name,
        version: selectedVersion.version,
        publisherId: package.publisherId,
        isDiscontinued: package.isDiscontinued,
        likes: package.likes),
  );
}

List<Tab> _pkgTabs(
  Package package,
  PackageVersion selectedVersion,
  AnalysisView analysis,
  bool isAdmin,
) {
  final card = analysis?.card;

  String renderedReadme;
  final packageLinks = selectedVersion.packageLinks;
  final baseUrl = packageLinks.baseUrl;
  if (selectedVersion.readme != null) {
    renderedReadme = renderFile(selectedVersion.readme, baseUrl);
  }

  String renderedChangelog;
  if (selectedVersion.changelog != null) {
    renderedChangelog = renderFile(selectedVersion.changelog, baseUrl);
  }

  String renderedExample;
  if (selectedVersion.example != null) {
    final exampleFilename = selectedVersion.example.filename;
    renderedExample = renderFile(selectedVersion.example, baseUrl);
    if (renderedExample != null) {
      final url = getRepositoryUrl(baseUrl, exampleFilename);
      final escapedName = htmlEscape.convert(exampleFilename);
      final link = url == null
          ? escapedName
          : '<a href="$url" target="_blank" rel="noopener noreferrer nofollow">$escapedName</a>';
      renderedExample = '<p style="font-family: monospace"><b>$link</b></p>\n'
          '$renderedExample';
    }
  }

  final tabs = <Tab>[];

  void addFileTab(String id, String title, String content) {
    if (content == null) return;
    tabs.add(Tab.withContent(
        id: id, title: title, contentHtml: content, isMarkdown: true));
  }

  addFileTab('readme', 'Readme', renderedReadme);
  addFileTab('changelog', 'Changelog', renderedChangelog);
  addFileTab('example', 'Example', renderedExample);

  tabs.add(Tab.withContent(
      id: 'installing',
      title: 'Installing',
      contentHtml: _renderInstallTab(selectedVersion, analysis?.derivedTags)));
  tabs.add(Tab.withLink(
    id: 'versions',
    title: 'Versions',
    href: urls.pkgVersionsUrl(selectedVersion.package),
  ));
  tabs.add(Tab.withContent(
    id: 'analysis',
    titleHtml: renderScoreBox(
      card?.overallScore,
      isSkipped: card?.isSkipped ?? false,
      isNewPackage: package.isNewPackage(),
      isTabHeader: true,
    ),
    contentHtml: renderAnalysisTab(selectedVersion.package,
        selectedVersion.pubspec.sdkConstraint, card, analysis),
  ));
  if (isAdmin) {
    tabs.add(Tab.withLink(
      id: 'admin',
      title: 'Admin',
      href: urls.pkgAdminUrl(selectedVersion.package),
    ));
  }
  return tabs;
}

String _getAuthorsHtml(List<String> authors) {
  return (authors ?? const []).map((String value) {
    final EmailAddress author = EmailAddress.parse(value);
    final escapedName = htmlEscape.convert(author.name ?? author.email);
    if (author.email != null) {
      final escapedEmail = htmlAttrEscape.convert(author.email);
      final emailSearchUrl = htmlAttrEscape.convert(
          SearchQuery.parse(query: 'email:${author.email}').toSearchLink());
      return '<span class="author">'
          '<a href="mailto:$escapedEmail" title="Email $escapedEmail">'
          '<i class="email-icon"></i></a> '
          '<a href="$emailSearchUrl" title="Search packages with $escapedEmail" rel="nofollow">'
          '<i class="search-icon"></i></a> '
          '$escapedName'
          '</span>';
    } else {
      return '<span class="author">$escapedName</span>';
    }
  }).join('<br/>');
}

String renderPackageSchemaOrgHtml(
    Package p, PackageVersion pv, AnalysisView analysis) {
  final Map map = {
    '@context': 'http://schema.org',
    '@type': 'SoftwareSourceCode',
    'name': pv.package,
    'version': pv.version,
    'description': '${pv.package} - ${pv.pubspec.description}',
    'url': urls.pkgPageUrl(pv.package, includeHost: true),
    'dateCreated': p.created.toIso8601String(),
    'dateModified': pv.created.toIso8601String(),
    'programmingLanguage': 'Dart',
    'image':
        '${urls.siteRoot}${staticUrls.staticPath}/img/dart-logo-400x400.png'
  };
  final licenses = analysis?.licenses;
  final firstUrl =
      licenses?.firstWhere((lf) => lf.url != null, orElse: () => null)?.url;
  if (firstUrl != null) {
    map['license'] = firstUrl;
  }
  // TODO: add http://schema.org/codeRepository for github and gitlab links
  return '<script type="application/ld+json">\n${json.encode(map)}\n</script>\n';
}
