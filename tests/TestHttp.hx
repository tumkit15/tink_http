package;

import haxe.DynamicAccess;
import tink.http.Method;
import tink.http.Client;
import tink.http.clients.*;
import tink.http.Response;
import tink.http.Request;
import tink.http.Header;
import tink.Chunk;
import tink.Url;
import tink.unit.*;

using tink.io.Source;
using tink.CoreApi;

@:timeout(20000)
@:asserts
class TestHttp {
  var client:Client;
  var url:Url;
  var converter:Converter;
  
  public function new(client:ClientType, target, secure) {
    this.client = switch client {
      #if sys
      case Socket: secure ? new SecureSocketClient() : new SocketClient();
      #end
      #if (js && !nodejs)
      case Js: secure ? new SecureJsClient() : new JsClient();
      #end
      #if nodejs
      case Node: secure ? new SecureNodeClient() : new NodeClient();
      #end
      #if tink_tcp
      case Tcp: secure ? new SecureTcpClient() : new TcpClient();
      #end
      #if ((nodejs || sys) && !php)
      case Curl: secure ? new SecureCurlClient() : new CurlClient();
      #end
      #if flash
      case Flash: secure ? new SecureFlashClient() : new FlashClient();
      #end
    }
    
    var schema = secure ? 'https' : 'http';
    switch target {
      case Httpbin:
        url = '$schema://httpbin.org';
        converter = new HttpbinConverter();
      case Local(port):
        url = '$schema://localhost:$port';
        converter = new LocalConverter();
    }
  }
  
  @:variant(GET)
  @:variant(POST)
  @:variant(PATCH)
  @:variant(DELETE)
  @:variant(PUT)
  public function method(method:Method) {
    var body:String = null;
    var headers = null;
    switch method {
      case GET: // do nothing
      default: 
        body = 'tink_http $method';
        headers = [
          new HeaderField('content-type', 'text/plain'),
          new HeaderField('content-length', Std.string(body.length)),
        ];
    }
    return request(method, url + '/${(method:String).toLowerCase()}?a=1&b=2', headers, body == null ? null : body)
      .next(function(echo) {
          asserts.assert(echo.query.get('a') == '1');
          asserts.assert(echo.query.get('b') == '2');
          if(body != null) asserts.assert(echo.body == body);
          return asserts.done();
      });
  }
  
  // @:include
  public function headers()
    return request(GET, url + '/headers', [new HeaderField('x-custom-tink', 'tink_http')])
      .next(function(echo) {
          asserts.assert(Type.enumEq(echo.headers.byName('x-custom-tink'), Success('tink_http')));
          return asserts.done();
      });
  
  public function origin()
    return request(GET, url + '/ip')
      .next(function(echo) {
          asserts.assert(echo.origin != null && echo.origin.length > 0);
          return asserts.done();
      });
  
  
  function request(method:Method, url:Url, ?headers:Array<HeaderField>, ?body:IdealSource) {
    if(headers == null) headers = [];
    var header = new OutgoingRequestHeader(method, url, headers);
    if(!header.byName(HOST).isSuccess()) headers.push(new HeaderField(HOST, url.host.toString()));
    return client.request(new OutgoingRequest(
      header,
      body == null ? Source.EMPTY : body
    )).next(converter.convert);
  }
  
}


enum Target {
  Httpbin;
  Local(port:Int);
}

interface Converter {
  function convert(res:IncomingResponse):Promise<EchoedRequest>;
}

class LocalConverter implements Converter {
  public function new() {}
  public function convert(res:IncomingResponse):Promise<EchoedRequest> {
    return res.body.all().next(function(chunk):EchoedRequest {
      // trace(chunk);
      var parsed:Data = haxe.Json.parse(chunk);
      
      return {
        headers: new Header(
          if(parsed.headers == null)
            []
          else
            [for(h in parsed.headers) new HeaderField(h.name, h.value)]
        ),
        query: {
          var map = new Map();
          if(parsed.query != null) for(name in parsed.query.keys()) map.set(name, parsed.query.get(name));
          map;
        },
        body: parsed.body == null ? Chunk.EMPTY : parsed.body,
        origin: parsed.ip,
      }
    });
  }
}

class HttpbinConverter implements Converter {
  public function new() {}
  public function convert(res:IncomingResponse):Promise<EchoedRequest> {
    return res.body.all().next(function(chunk):EchoedRequest {
      // trace(chunk);
      var parsed: {
        headers:DynamicAccess<String>,
        args:DynamicAccess<String>,
        data:String,
        origin:String,
      } = haxe.Json.parse(chunk);
      
      return {
        headers: new Header(
          if(parsed.headers == null)
            []
          else
            [for(name in parsed.headers.keys()) new HeaderField(name, parsed.headers.get(name))]
        ),
        query: {
          var map = new Map();
          if(parsed.args != null) for(name in parsed.args.keys()) map.set(name, parsed.args.get(name));
          map;
        },
        body: parsed.data == null ? Chunk.EMPTY : parsed.data,
        origin: parsed.origin,
      }
    });
  }
}

typedef EchoedRequest = {
  headers:Header,
  query:Map<String, String>,
  body:Chunk,
  origin:String,
}