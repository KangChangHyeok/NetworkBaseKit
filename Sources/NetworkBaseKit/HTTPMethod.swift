//
//  File.swift
//  NetworkKit
//
//  Created by changhyeok on 1/23/26.
//

import Foundation

public enum HTTPMethod: String, Sendable, CaseIterable {
    case get     = "GET"
    case post    = "POST"
    case put     = "PUT"
    case patch   = "PATCH"
    case delete  = "DELETE"
    case head    = "HEAD"
    case options = "OPTIONS"
}
