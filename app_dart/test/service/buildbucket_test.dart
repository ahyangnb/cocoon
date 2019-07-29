// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cocoon_service/src/datastore/cocoon_config.dart';
import 'package:cocoon_service/src/model/luci/buildbucket.dart';
import 'package:cocoon_service/src/request_handling/body.dart';
import 'package:cocoon_service/src/service/access_token_provider.dart';
import 'package:cocoon_service/src/service/buildbucket.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../src/request_handling/fake_authentication.dart';

void main() {
  group('Client tests', () {
    MockHttpClient mockHttpClient;
    MockAccessTokenProvider mockAccessTokenProvider;
    MockConfig mockConfig;

    const BuilderId builderId = BuilderId(
      bucket: 'prod',
      builder: 'Linux',
      project: 'flutter',
    );

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockAccessTokenProvider = MockAccessTokenProvider();
      mockConfig = MockConfig();
    });

    Future<T> _httpTest<R extends Body, T>(
      R request,
      String response,
      String expectedPath,
      Future<T> Function(BuildBucketClient) requestCallback,
    ) async {
      when(mockAccessTokenProvider.createAccessToken(any,
              serviceAccountJson: anyNamed('serviceAccountJson'), scopes: anyNamed('scopes')))
          .thenAnswer((_) async {
        return AccessToken('Bearer', 'data', DateTime.utc(2119));
      });
      final BuildBucketClient client = BuildBucketClient(
        FakeClientContext(isDevelopmentEnvironment: false),
        mockConfig,
        buildBucketUri: 'https://localhost',
        httpClient: mockHttpClient,
        accessTokenProvider: mockAccessTokenProvider,
      );
      final MockHttpClientRequest mockHttpRequest = MockHttpClientRequest();
      final MockHttpClientResponse mockHttpResponse = MockHttpClientResponse(utf8.encode(response));
      when(mockHttpResponse.statusCode).thenReturn(202);
      when(mockHttpClient.postUrl(argThat(equals(Uri.parse('https://localhost/$expectedPath')))))
          .thenAnswer((_) => Future<MockHttpClientRequest>.value(mockHttpRequest));
      when(mockHttpRequest.close())
          .thenAnswer((_) => Future<MockHttpClientResponse>.value(mockHttpResponse));
      final T result = await requestCallback(client);

      expect(mockHttpRequest.headers.value('content-type'), 'application/json');
      expect(mockHttpRequest.headers.value('accept'), 'application/json');
      expect(mockHttpRequest.headers.value('authorization'), 'Bearer data');
      verify(mockHttpRequest.write(argThat(equals(json.encode(request.toJson()))))).called(1);
      return result;
    }

    test('Throws the right exception', () async {
      when(mockAccessTokenProvider.createAccessToken(any,
              serviceAccountJson: anyNamed('serviceAccountJson'), scopes: anyNamed('scopes')))
          .thenAnswer((_) async {
        return AccessToken('Bearer', 'data', DateTime.utc(2119));
      });
      final BuildBucketClient client = BuildBucketClient(
        FakeClientContext(isDevelopmentEnvironment: false),
        mockConfig,
        buildBucketUri: 'https://localhost',
        httpClient: mockHttpClient,
        accessTokenProvider: mockAccessTokenProvider,
      );
      final MockHttpClientRequest mockHttpRequest = MockHttpClientRequest();
      final MockHttpClientResponse mockHttpResponse = MockHttpClientResponse(utf8.encode('Error'));
      when(mockHttpResponse.statusCode).thenReturn(403);
      when(mockHttpClient.postUrl(argThat(equals(Uri.parse('https://localhost/Batch')))))
          .thenAnswer((_) => Future<MockHttpClientRequest>.value(mockHttpRequest));
      when(mockHttpRequest.close())
          .thenAnswer((_) => Future<MockHttpClientResponse>.value(mockHttpResponse));
      try {
        await client.batch(const BatchRequest());
      } on BuildBucketException catch (ex) {
        expect(ex.statusCode, 403);
        expect(ex.message, 'Error');
        return;
      }
      fail('Did not throw expected exception');
    });

    test('ScheduleBuild', () async {
      const ScheduleBuildRequest request = ScheduleBuildRequest(
        builderId: builderId,
        experimental: Trinary.yes,
        tags: <String, List<String>>{
          'user_agent': <String>['flutter_cocoon'],
          'flutter_pr': <String>['true', '1']
        },
        properties: <String, String>{
          'git_url': 'https://github.com/flutter/flutter',
          'git_ref': 'pull/1/head',
        },
      );

      final Build build = await _httpTest<ScheduleBuildRequest, Build>(
        request,
        buildJson,
        'ScheduleBuild',
        (BuildBucketClient client) => client.scheduleBuild(request),
      );
      expect(build.id, 123);
      expect(build.tags.length, 2);
    });

    test('CancelBuild', () async {
      const CancelBuildRequest request = CancelBuildRequest(
        id: 1234,
        summaryMarkdown: 'Because I felt like it.',
      );

      final Build build = await _httpTest<CancelBuildRequest, Build>(
        request,
        buildJson,
        'CancelBuild',
        (BuildBucketClient client) => client.cancelBuild(request),
      );

      expect(build.id, 123);
      expect(build.tags.length, 2);
    });

    test('Batch', () async {
      const BatchRequest request = BatchRequest(requests: <Request>[
        Request(getBuild: GetBuildRequest(builderId: builderId, buildNumber: 123)),
      ]);

      final BatchResponse response = await _httpTest<BatchRequest, BatchResponse>(
        request,
        batchJson,
        'Batch',
        (BuildBucketClient client) => client.batch(request),
      );

      expect(response.responses.length, 1);
      expect(response.responses.first.getBuild.status, Status.success);
    });

    test('GetBuild', () async {
      const GetBuildRequest request = GetBuildRequest(
        id: 1234,
      );

      final Build build = await _httpTest<GetBuildRequest, Build>(
        request,
        buildJson,
        'GetBuild',
        (BuildBucketClient client) => client.getBuild(request),
      );

      expect(build.id, 123);
      expect(build.tags.length, 2);
    });

    test('SearchBuilds', () async {
      const SearchBuildsRequest request = SearchBuildsRequest(
        predicate: BuildPredicate(
          tags: <String, List<String>>{
            'flutter_pr': <String>['1'],
          },
        ),
      );

      final SearchBuildsResponse response =
          await _httpTest<SearchBuildsRequest, SearchBuildsResponse>(
        request,
        searchJson,
        'SearchBuilds',
        (BuildBucketClient client) => client.searchBuilds(request),
      );

      expect(response.builds.length, 1);
      expect(response.builds.first.number, 9151);
    });
  });
}

const String searchJson = '''${BuildBucketClient.kRpcResponseGarbage}
{
  "builds": [
    {
      "status": "SUCCESS",
      "updateTime": "2019-07-26T20:43:52.875240Z",
      "createdBy": "project:flutter",
      "builder": {
        "project": "flutter",
        "builder": "Linux",
        "bucket": "prod"
      },
      "number": 9151,
      "id": "8906840690092270320",
      "startTime": "2019-07-26T20:10:22.271996Z",
      "input": {
        "gitilesCommit": {
          "project": "external/github.com/flutter/flutter",
          "host": "chromium.googlesource.com",
          "ref": "refs/heads/master",
          "id": "3068fc4f7c78599ab4a09b096f0672e8510fc7e6"
        }
      },
      "endTime": "2019-07-26T20:43:52.341494Z",
      "createTime": "2019-07-26T20:10:15.744632Z"
    }
  ]
}''';
const String batchJson = '''${BuildBucketClient.kRpcResponseGarbage}
{
  "responses": [
    {
      "getBuild": {
        "status": "SUCCESS",
        "updateTime": "2019-07-15T23:20:56.930928Z",
        "createdBy": "project:flutter",
        "builder": {
          "project": "flutter",
          "builder": "Linux",
          "bucket": "prod"
        },
        "number": 9000,
        "id": "8907827286280251904",
        "startTime": "2019-07-15T22:49:06.222424Z",
        "input": {
          "gitilesCommit": {
            "project": "external/github.com/flutter/flutter",
            "host": "chromium.googlesource.com",
            "ref": "refs/heads/master",
            "id": "6b17840cbf1a7d7b6208117226ded21a5ec0d55c"
          }
        },
        "endTime": "2019-07-15T23:20:32.610402Z",
        "createTime": "2019-07-15T22:48:44.299749Z"
      }
    }
  ]
}''';

const String buildJson = '''${BuildBucketClient.kRpcResponseGarbage}
{
  "id": "123",
  "builder": {
    "project": "flutter",
    "bucket": "prod",
    "builder": "Linux"
  },
  "number": 321,
  "createdBy": "cocoon@cocoon",
  "canceledBy": null,
  "startTime": "2019-08-01T11:00:00",
  "endTime": null,
  "status": "SCHEDULED",
  "input": {
    "experimental": "YES"
  },
  "tags": [{
    "key": "user_agent",
    "value": "flutter_cocoon"
  }, {
    "key": "flutter_pr",
    "value": "1"
  }]
}''';

class MockHttpClient extends Mock implements HttpClient {}

class MockHttpClientRequest extends Mock implements HttpClientRequest {
  final FakeHttpHeaders _fakeHeaders = FakeHttpHeaders();
  @override
  HttpHeaders get headers => _fakeHeaders;
}

class FakeHttpHeaders extends HttpHeaders {
  final Map<String, String> _headers = <String, String>{};

  @override
  List<String> operator [](String name) {
    return null;
  }

  @override
  void add(String name, Object value) {
    _headers[name] = value;
  }

  @override
  void clear() {}

  @override
  void forEach(void Function(String name, List<String> values) f) {}

  @override
  void noFolding(String name) {}

  @override
  void remove(String name, Object value) {}

  @override
  void removeAll(String name) {}

  @override
  void set(String name, Object value) {}

  @override
  String value(String name) {
    return _headers[name];
  }
}

class MockHttpClientResponse extends Mock implements HttpClientResponse {
  MockHttpClientResponse(this.response);

  final Uint8List response;

  @override
  StreamSubscription<Uint8List> listen(
    void onData(Uint8List event), {
    Function onError,
    void onDone(),
    bool cancelOnError,
  }) {
    return Stream<Uint8List>.fromFuture(Future<Uint8List>.value(response))
        .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class MockAccessTokenProvider extends Mock implements AccessTokenProvider {}

// ignore: must_be_immutable
class MockConfig extends Mock implements Config {}