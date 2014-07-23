//
//  Auth.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/11/14.
//  Copyright (c) 2014 SMART Platforms. All rights reserved.
//

import Foundation
import OAuth2iOS			// TODO: figure out a way to use the iOS framework as simply "OAuth2"


enum AuthMethod {
	case None
	case ImplicitGrant
	case CodeGrant
}


/**
 *  Describes the authentication to be used.
 */
class Auth {
	
	/** The authentication type; only "oauth2" is supported. */
	let type: AuthMethod
	
	/** The scopes needed; supply a space-separated list just as if supplying directly to OAuth2. */
	let scope: String
	
	/** The redirect to be used. */
	let redirect: String
	
	/** Additional settings to be used to initialize the OAuth2 subclass. */
	let settings: NSDictionary
	
	/** The authentication object to be used. */
	var oauth: OAuth2?
	
	/** The closure to call when authorization finishes. */
	var authCallback: ((patientId: String?, error: NSError?) -> ())?
	
	init(type: AuthMethod, scope: String, redirect: String, settings: NSDictionary) {
		self.type = type
		self.scope = scope
		self.redirect = redirect
		self.settings = settings
	}
	
	
	var clientId: String? {
		get { return oauth?.clientId }
	}
	
	var patientId: String?
	
	
	// MARK: - OAuth
	
	func create(# authURL: NSURL, tokenURL: NSURL?) {
		// TODO: make a nice factory method
		var settings = self.settings.mutableCopy() as NSMutableDictionary
		settings["authorize_uri"] = authURL.absoluteString
		if tokenURL {
			settings["token_uri"] = tokenURL!.absoluteString
		}
		//settings["redirect_uris"] = [redirect]
		
		switch type {
		case .CodeGrant:
			oauth = OAuth2CodeGrant(settings: settings)
			oauth!.onAuthorize = { parameters in
				if let patient = parameters["patient"] as? String {
					logIfDebug("Did receive patient id \(patient)")
					self.authCallback?(patientId: patient, error: nil)
				}
				else {
					logIfDebug("Did handle redirect but do not have a patient context, returning without patient")
					self.authCallback?(patientId: nil, error: nil)
				}
				self.authCallback = nil
			}
			oauth!.onFailure = { error in
				self.authCallback?(patientId: nil, error: error)
				self.authCallback = nil
			}
		default:
			fatalError("Invalid auth method type")
		}
		
#if DEBUG
		oauth!.verbose = true
#endif
	}
	
	func authorizeURL() -> NSURL? {
		return oauth?.authorizeURLWithRedirect(redirect, scope: scope, params: nil)
	}
	
	/**
	 *  Starts the authorization flow, either by opening an embedded web view or switching to the browser.
	 *
	 *  If you set `embedded` to false remember that you need to intercept the callback from the browser and call
	 *  the client's `didRedirect()` method, which redirects to this instance's `handleRedirect()` method.
	 */
	func authorize(embedded: Bool, callback: (patientId: String?, error: NSError?) -> Void) {
		if authCallback {
			authCallback!(patientId: nil, error: genSMARTError("Timeout", nil))
			authCallback = nil
		}
		
		if oauth {
			authCallback = callback
			if embedded {
				authorizeEmbedded(oauth!)
			}
			else {
				openURLInBrowser(authorizeURL()!)
			}
		}
		else {
			callback(patientId: nil, error: genSMARTError("I am not yet set up to authorize, missing a handle to my OAuth2 instance", nil))
		}
	}
	
	func handleRedirect(redirect: NSURL) -> Bool {
		if !oauth || !authCallback {
			return false
		}
		
		oauth!.handleRedirectURL(redirect)
		return true
	}
	
	func abort() {
		if authCallback {
			authCallback!(patientId: nil, error: nil)
			authCallback = nil
		}
	}
	
	
	// MARK: - Requests
	
	func signedRequest(url: NSURL) -> NSMutableURLRequest {
		return oauth!.request(forURL: url)
	}
}

