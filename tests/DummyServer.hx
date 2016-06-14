package;

import haxe.io.Bytes;
import tink.http.Header;
import tink.http.Request;
import tink.http.Response;
import tink.io.Buffer;
import tink.io.Sink;
import haxe.io.BytesOutput;
import tink.io.Worker;

using tink.CoreApi;

class DummyServer {
	
  public static function main()
    Server.main();
  
  static public function handleRequest(req:IncomingRequest):Future<OutgoingResponse> {
	return Future.sync(('ok': OutgoingResponse));
    return 
      if (req.header.uri == '/close') {
        Sys.exit(0);
        null;
      }
      else switch req.body {
        case Plain(src):
			if (!Reflect.hasField(src, 'surplus')) {
				Future.sync(('empty body': OutgoingResponse));
			} else
          src.all().map(function (o) return switch o {
            case Success(body):
              var data:Data = {
                uri: req.header.uri.toString(),
                ip: req.clientIp,
                method: req.header.method,
                headers: [for (h in req.header.fields) { name: h.name, value: h.value } ], 
                body: body.toString(),
              };
              OutgoingResponse.blob(Bytes.ofString(haxe.Json.stringify(data)), 'application/json');
            case Failure(e):
              new OutgoingResponse(
                new ResponseHeader(e.code, e.message, [new HeaderField('content-type', 'application/json')]),
                haxe.Json.stringify( {
                  error: true,
                  code: e.code, 
                  message: e.message
                })
              );
          });
        case Parsed(parts):
          var data:Data = {
            uri: req.header.uri.toString(),
            ip: req.clientIp,
            method: req.header.method,
            headers: [for (h in req.header.fields) { name: h.name, value: h.value } ], 
            body: haxe.Json.stringify([for (p in parts) {
              name: p.name,
              value: switch p.value {
                case Value(s): s;
                case File(u): u.fileName + '=' + u.mimeType;
              }
            }]),
          };            
          Future.sync(OutgoingResponse.blob(Bytes.ofString(haxe.Json.stringify(data)), 'application/json'));
      }
  }
  
}