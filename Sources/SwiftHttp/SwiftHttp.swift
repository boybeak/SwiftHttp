// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

@available(macOS 13.0, *)
public class SwiftHttp {
    
    private var requestMap = [UUID : Any]()
    
    public init() {}
    
    public func get<T : Decodable>(urlStr: String, headers: [String : String]? = nil, params: [String : String]? = nil)-> Call<T> {
        return request(urlStr: urlStr, headers: headers, params: params, method: .GET)
    }
    
    public func post<T : Decodable>(urlStr: String, headers: [String : String]? = nil, params: [String : String]? = nil)-> Call<T> {
        return request(urlStr: urlStr, headers: headers, params: params, method: .POST)
    }
    
    public func request<T : Decodable>(urlStr: String, headers: [String : String]?, params: [String : String]?, method: HttpMethod)-> Call<T> {
        guard var url = URL(string: urlStr) else {
            fatalError("Illegal urlStr=\(urlStr)")
        }
        
        if method == .GET, let paramsMap = params {
            var queryItems = [URLQueryItem]()
            paramsMap.forEach {k, v in
                queryItems.append(URLQueryItem(name: k, value: v))
            }
            url.append(queryItems: queryItems)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        if let headersMap = headers {
            headersMap.forEach { name, value in
                request.addValue(value, forHTTPHeaderField: name)
            }
        }
        
        if method == .POST, let paramsMap = params {
            // 将参数编码为 application/x-www-form-urlencoded 格式
            let parameterArray = paramsMap.map { (key, value) -> String in
                return "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            let postString = parameterArray.joined(separator: "&")
            request.httpBody = postString.data(using: .utf8)

            // 设置请求头
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        
        let call = Call<T>(request: request, map: requestMap)
        
        return call
    }
}

public class Call<T> where T : Decodable {
    
    private var startCallback: (() -> Void)? = nil
    private var respCallback: ((Data?, URLResponse?, Error?) -> Void)? = nil
    private var resultCallback: ((T) -> Void)? = nil
    private var errorCallback: ((Error?) -> Void)? = nil
    
    let request: URLRequest
    private lazy var task: URLSessionDataTask = {
        return URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                self?.release()
            }
            
            self?.actionResponse(data: data, response: response, error: error)
            
            if let e = error {
                self?.actionError(error: error)
                return
            }
            
            if let d = data {
                do {
                    try self?.actionResult(d: d)
                } catch let error {
                    let str = String(data: d, encoding: .utf8)
                    self?.actionError(error: ParseError(message: "\(error.localizedDescription) - \(str ?? "")"))
                }
            } else {
                self?.actionError(error: error)
            }
        }
    }()
    
    private let callId: UUID
    private var requestMap: [UUID : Any]
    
    init (request: URLRequest, map: [UUID : Any]) {
        self.request = request
        self.callId = UUID()
        self.requestMap = map
    }
    
    public func start() {
        if requestMap.contains(where: { $0.key == callId }) {
            return
        }
        self.task.resume()
        requestMap[callId] = self
        actionStart()
    }
    
    public func release() {
        DispatchQueue.main.async {
            self.requestMap.removeValue(forKey: self.callId)
            self.startCallback = nil
            self.respCallback = nil
            self.resultCallback = nil
            self.errorCallback = nil
        }
    }
    
    public func onStart(callback: @escaping ()-> Void)-> Call<T> {
        self.startCallback = callback
        return self
    }
    
    private func actionStart() {
        self.startCallback?()
        self.startCallback = nil
    }
    
    public func onResponse(callback: @escaping (Data?, URLResponse?, Error?)-> Void)-> Call<T> {
        self.respCallback = callback
        return self
    }
    
    private func actionResponse(data: Data?, response: URLResponse?, error: Error?) {
        DispatchQueue.main.async {
            self.respCallback?(data, response, error)
        }
    }
    
    public func onResult(callback: @escaping (T) -> Void)-> Call<T> {
        self.resultCallback = callback
        return self
    }
    
    private func actionResult(d: Data) throws {
        let t: T = try JSONDecoder().decode(T.self, from: d)
        DispatchQueue.main.async {
            self.resultCallback?(t)
        }
    }
    
    public func onError(callback: @escaping (Error?) -> Void)-> Call<T> {
        self.errorCallback = callback
        return self
    }
    
    private func actionError(error: Error?) {
        DispatchQueue.main.async {
            self.errorCallback?(error)
        }
    }
}

public enum HttpMethod : String {
    case GET, POST
}

public struct ParseError: Error {
    let message: String
}
