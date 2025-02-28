//
//  FSCheckoutSheet.swift
//
//  Created by Helge Heß on 30.05.20.
//

#if os(macOS)
import Cocoa
import WebKit

/**
 * A view controller used to drive a sheet to perform a checkout on the
 * FastSpring store.
 * Allows preconfiguring a product (and its quantity) to checkout.
 *
 * Usage from within another NSViewController:
 *
 *     let vc = FastSpringCheckoutVC()
 *     vc.checkoutProduct("soy-for-community-slacks",
 *                        in: "zeezide.onfastspring.com") {
 *         licenseKeys in
 *
 *         for licenseKey in licenseKeys {
 *             print("User",   licenseKey.name,
 *                   "bought", licenseKey.sku,
 *                   "code:",  licenseKey.code)
 *         }
 *     }
 *     self.presentAsSheet(vc)
 *
 * Note: Currently this is only reporting CocoaFob licenses.
 */
public final class FastSpringCheckoutVC: NSViewController {
  // ToS and PP links do not work? (would navigate to other page?)
  
  /**
   * Represents a purchased license, that is:
   * - its SKU as specified in the FastSpring admin panel
   * - the license name and license code generated by FastSpring
   */
  public struct LicenseKey {
    /// The SKU of the license as specified in the FastSpring admin panel
    public let sku  : String
    /// The license name as determined by FastSpring during checkout
    public let name : String
    /// The generated CocoaFob code
    public let code : String
  }
  
  /**
   * Configure the view controller for the checkout of a given product.
   *
   * - Parameter productPath: The (internal) name of the product, e.g. "soy-for-community-slacks"
   * - Parameter quantity: The product quantity to preconfigure (defaults to 1)
   * - Parameter storeFront: The name of the storefront, e.g. "zeezide.onfastspring.com"
   * - Parameter yield:
   *     A closure called to be called when the sheet is closed,
   *     containing the licenses keys the customer bought.
   *     (empty if the customer cancelled).
   * - Returns: `self`, the view controller (discardable)
   */
  @discardableResult
  public func checkoutProduct(_ productPath: String, quantity: Int = 1,
                              in storeFront: String,
                              yield : @escaping
                              ( _ licenseKeys: Result<[ LicenseKey ], Error> ) -> Void)
  -> Self
  {
    assert(callback == nil, "callback already set!")
    callback = yield
    
    _ = view // make sure it is loaded!
    
    assert(webView != nil)
    webView?.loadFastSpringCheckout(for: storeFront, productPath: productPath,
                                    quantity: quantity)
    return self
  }
  
  
  private var webView : WKWebView?
  
  private func dismiss() {
    if let pvc = presentingViewController {
      pvc.dismiss(self)
    }
    else if isViewLoaded, let window = view.window {
      window.close()
    }
    webView  = nil
    callback = nil
  }
  
  public override func cancelOperation(_ sender: Any?) {
    guard isViewLoaded else { return }
    dismiss()
  }
  
  public override func viewWillAppear() {
    super.viewWillAppear()
	  self.showLoadingProgress = true
  }
  public override func viewDidDisappear() {
    super.viewDidDisappear()
    emit(.success([]))
  }
  
  private var callback : (( _ licenseKeys: Result<[ LicenseKey ], Error> ) -> Void)?
  
  private func emit(_ keys: Result<[ LicenseKey ], Error>) {
    guard let cb = callback else { return }
    if case .success = keys {
      callback = nil
    }
    cb(keys)
  }
  
  private let spinner : NSProgressIndicator = {
    let spinner = NSProgressIndicator()
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.style = .spinning
	  spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    return spinner
  }()
	
	private let loadingLabel: NSTextField = {
		let label = NSTextField(labelWithString: NSLocalizedString("Loading…", comment: "Store web view loading label"))
		return label
	}()
	
	private var showLoadingProgress: Bool = false {
		didSet {
			if showLoadingProgress {
				self.spinner.startAnimation(nil)
				self.loadingLabel.isHidden = false
			} else {
				self.spinner.stopAnimation(nil)
				self.loadingLabel.isHidden = true
			}
		}
	}
  
	public override func loadView() {
		let config : WKWebViewConfiguration = {
			let prefs = WKPreferences()
			prefs.javaScriptCanOpenWindowsAutomatically = true
			prefs.javaScriptEnabled = true
			prefs.javaEnabled       = false
			prefs.plugInsEnabled    = false
			
			let controller = WKUserContentController()
			controller.addUserScript(
				WKUserScript(source           : FindLicenseJavaScript,
							 injectionTime    : .atDocumentStart,
							 forMainFrameOnly : true)
			)
			controller.add(self, name: "zz")
			
			let config = WKWebViewConfiguration()
			config.preferences = prefs
			config.allowsAirPlayForMediaPlayback  = false
			config.suppressesIncrementalRendering = true
			
			config.userContentController = controller
			return config
		}()
		
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.translatesAutoresizingMaskIntoConstraints = true
		webView.autoresizingMask   = [.width, .height]
		webView.navigationDelegate = self
		
		let buttonStack = NSStackView()
		buttonStack.orientation = .horizontal
		buttonStack.distribution = .gravityAreas
		buttonStack.alignment   = .centerY
		buttonStack.detachesHiddenViews = true
		buttonStack.edgeInsets  =
		NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
		let button = NSButton(title  : "Dismiss", // TODO: Loc
							  target : nil, action: #selector(cancelOperation(_:)))
		buttonStack.addView(button, in: .trailing)
		buttonStack.addView(loadingLabel, in: .leading)
		buttonStack.addView(spinner, in: .leading)
		
		let sep = NSBox(frame: .zero)
		sep.boxType = .separator
		
		let pageStack = NSStackView(views: [ webView, sep, buttonStack ])
		pageStack.orientation = .vertical
		pageStack.alignment   = .width
		pageStack.spacing     = 0
		
		self.webView = webView
		self.view    = pageStack
		
		let hc = view.widthAnchor .constraint(equalToConstant: 1024)
		let wc = view.heightAnchor.constraint(equalToConstant: 768)
		
		NSLayoutConstraint.activate([
			wc, hc,
			view.widthAnchor .constraint(greaterThanOrEqualToConstant: 800),
			view.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),
			sep .heightAnchor.constraint(equalToConstant: 1),
			buttonStack.widthAnchor.constraint(equalTo: pageStack.widthAnchor, multiplier: 1.0)
			
			//      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			//      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
		])
	}
  
  struct ViewData: Codable {
    let debtorName: String?
    let order: Order
  }
  
  struct Order: Codable {
    let groups: [Group]
  }
  
  struct Group: Codable {
    let items: [Item]
  }
  
  struct Item: Codable {
    let fulfillment: Fulfillment?
  }
  
  struct Fulfillment: Codable {
    let licenses: [License]
  }
  
  struct License: Codable {
    let code: String
  }
  
  public static func parseScriptResult(_ anyJSON: Any) throws -> [LicenseKey]? {
    guard let jsonString = anyJSON as? String else {
      throw NSError(description: "JSON not a string")
    }
    guard let jsonData = jsonString.data(using: .utf8) else {
      throw NSError(description: "Coludn't create JSON data")
    }
    let jsonDecoder = JSONDecoder()
    let viewData = try jsonDecoder.decode(ViewData.self, from: jsonData)
    guard let name = viewData.debtorName else {
      return nil
    }
    let licenseKeys = viewData.order.groups.flatMap { group in
      group.items.flatMap { item in
        (item.fulfillment?.licenses ?? []).map { license in
          LicenseKey(sku: "", name: name, code: license.code)
        }
      }
    }
    return licenseKeys
  }
  
  fileprivate func handleScriptResult(_ anyJSON: Any) {
    do {
      if let licenseKeys = try Self.parseScriptResult(anyJSON) {
        emit(.success(licenseKeys))
      }
    } catch {
      emit(.failure(error))
    }
  }
  
  fileprivate func handleScriptResult_old(_ anyJSON: Any) {
    guard let licensesJSON = anyJSON as? [ [ String: Any ] ] else {
      print("FSCheckout: could not decode JSON:", anyJSON)
      return
    }
    guard !licensesJSON.isEmpty else { return }
    
    let licenses : [ LicenseKey ] = licensesJSON.compactMap { json in
      assert(json["licenseType"] as? String == "CocoaFob_license")
      assert(json["type"]        as? String == "license")
      
      if let type = json["type"] as? String {
        guard type == "license" else { return nil }
      }
      
      guard let name = json["licenseName"] as? String,
            let code = json["license"]     as? String,
            let sku  = json["sku"]         as? String else {
        print("FSCheckout: Could not decode license JSON:", anyJSON)
        return nil
      }
      return LicenseKey(sku: sku, name: name, code: code)
    }
    
    if !licenses.isEmpty {
      emit(.success(licenses))
      dismiss()
    }
  }
}

extension FastSpringCheckoutVC: WKNavigationDelegate {
  
  public
  func webView(_ webView: WKWebView,
               didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error)
  {
    // TODO: show error, and link to webstore
    print("FSCheckout: failed prov nav:", error, navigation as Any)
	  self.showLoadingProgress = false
  }
  
  private func isBlank() -> Bool {
    guard let url = webView?.url else { return true }
    return url.absoluteString == "about:blank"
  }
  
  public func webView(_ webView: WKWebView, didFinish n: WKNavigation!) {
	  if !isBlank() { self.showLoadingProgress = false }
  }
  
  public func webView(_ webView: WKWebView, didFail n: WKNavigation!,
                      withError error: Error)
  {
    // TODO: show error?
    print("FSCheckout: failed nav:", error,
          webView.url?.absoluteString ?? "")
	  self.showLoadingProgress = false
  }
  
  public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
//    print("FSCheckout: navigation to \(navigationAction)")
	  //Open links to things like privacy policy, invoice, etc. in web browser
	  if let url = navigationAction.request.url, navigationAction.targetFrame == nil {
		  NSWorkspace.shared.open(url)
	  }
	  return .allow
  }
}

extension FastSpringCheckoutVC: WKScriptMessageHandler {
  
  public func userContentController(_ ucc: WKUserContentController,
                                    didReceive message: WKScriptMessage)
  {
    guard message.name == "zz" else { assert(message.name == "zz"); return }
    handleScriptResult(message.body)
  }
}

fileprivate extension WKWebView {
  
  /**
   * Load the FastSpring checkout page into the WKWebView.
   *
   * The product and the quantity is preconfigured for checkout.
   *
   * Note: Arguments are not escaped in any way.
   *
   * - Parameter storeFront: The name of the storefront, e.g. "zeezide.onfastspring.com"
   * - Parameter productPath: The (internal) name of the product, e.g. "soy-for-community-slacks"
   * - Parameter quantity: The product quantity to preconfigure (defaults to 1)
   */
  func loadFastSpringCheckout(for storeFront : String,
                              productPath    : String,
                              quantity       : Int = 1)
  {
    let page = CheckoutPageHTML(for: storeFront, productPath: productPath,
                                quantity: quantity)
    loadHTMLString(page, baseURL: nil) // no base URL to distinguish this
  }
}

private extension NSError {
  convenience init(description: String) {
    self.init(domain: NSCocoaErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: description])
  }
}

#endif // macOS
