//The MIT License (MIT)
//
//Copyright (c) 2016 Webtrekk GmbH
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the
//"Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish,
//distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject
//to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//  Created by arsen.vartbaronov on 30/11/16.
//
//

import WatchKit

internal final class ProductListTrackerImpl: ProductListTracker {
    private var ecommerceProperties = [EcommerceProperties.Status: EcommerceProperties]()
    private let orderSaver = ProductOrderSaver()
    
    func addTrackingData(products: [EcommerceProperties.Product], type: EcommerceProperties.Status) {
        
        let productResults = products.filter(){ (product) -> Bool in
            guard let productId = product.name else {
                WebtrekkTracking.defaultLogger.logError("product without product id can't be tracked")
                return false
            }
            
            guard !(type == .list && product.position == nil)  else {
                WebtrekkTracking.defaultLogger.logError("product \(productId) without product position in list can't be tracked")
                return false
            }
            return true
        }
        
        if let _ = self.ecommerceProperties[type] {
            self.ecommerceProperties[type]?.products?.append(contentsOf: productResults)
        } else{
            self.ecommerceProperties[type] = EcommerceProperties(products: productResults)
        }
    }
    
    #if !os(watchOS)
    typealias UIController = UIViewController
    #else
    typealias UIController = WKInterfaceController
    #endif

    func track(commonProperties: PageViewEvent, viewController: UIController? = nil) {
        let webtrekk = WebtrekkTracking.instance()
        //setup ecommens status for each properties
        self.ecommerceProperties.forEach(){(key, value) in
            var ecommercePropertiesResult = commonProperties.ecommerceProperties
            ecommercePropertiesResult = ecommercePropertiesResult.merged(over: value)
            
            if ecommercePropertiesResult.status == nil {
                ecommercePropertiesResult.status = key
            }
            
            //check if there is products in list if no skeep tracking
            guard let _ = ecommercePropertiesResult.products else {
                WebtrekkTracking.logger.logError("Tracking won't be done. No products to track. Please call addTrackingData with products before this call")
                return
            }
            
            let count = ecommercePropertiesResult.products!.count
            
            //update position, save position or add order
            for i in 0..<count {
                let name = ecommercePropertiesResult.products![i].name
                if key != .list {
                    ecommercePropertiesResult.products![i].position = key == .viewed ? self.orderSaver.getLastPosition(product: name) :  self.orderSaver.getFirstPosition(product: name)
                    if key == .addedToBasket {
                        self.orderSaver.saveAddOrder(product: ecommercePropertiesResult.products![i])
                    }
                } else {//equal to list
                    self.orderSaver.savePositions(product: ecommercePropertiesResult.products![i])
                }
            }
            self.orderSaver.save()

            if key == .purchased {
                //resort
                ecommercePropertiesResult.products!.sort(){(product1, product2) in
                    return self.orderSaver.getAddOrder(product: product1.name) < self.orderSaver.getAddOrder(product: product2.name)
                }
            }
            
            //send

            let pageEvent = PageViewEvent (
                pageProperties: commonProperties.pageProperties,
                advertisementProperties: commonProperties.advertisementProperties,
                ecommerceProperties: ecommercePropertiesResult,
                ipAddress: commonProperties.ipAddress,
                sessionDetails: commonProperties.sessionDetails,
                userProperties: commonProperties.userProperties,
                variables: commonProperties.variables)

            if let controller = viewController {
                let tracker = WebtrekkTracking.trackerForAutotrackedViewController(controller)
                tracker.trackPageView(pageEvent)
            } else {
                webtrekk.trackPageView(pageEvent)
            }
            
            if key == .purchased {
                self.orderSaver.deleteAll()
            }
        }
        self.ecommerceProperties.removeAll()
    }
    
    
    private class ProductOrderSaver{
        private struct Order{
            var addOrder = Int.max
            var positionFirstValue : Int?
            var positionLastValue : Int?
            
            init(positionFirstValue: Int?){
                self.positionFirstValue = positionFirstValue
            }

            init(addOrder: Int){
                self.addOrder = addOrder
            }
            
            init(addOrder: Int, positionFirstValue : Int?, positionLastValue : Int?){
                self.addOrder = addOrder
                self.positionFirstValue = positionFirstValue
                self.positionLastValue = positionLastValue
            }
        }
        private var products  = [String : Order]()
        private var currentAddPosition = 0
        
        
        func load(){
            var maxOrder = -1
            self.products.removeAll()
            if let data = self.userDefaults.dataForKey(DefaultsKeys.productListOrder),
                let jsonObj = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String:Any?]] {
                
                jsonObj?.forEach(){ (item) in
                    if let name = item["id"] as? String {
                        
                        let addOrder = item["add_order"] as? Int
                    
                        let order = Order(addOrder: addOrder ?? Int.max,
                                      positionFirstValue: item["p_first"] as? Int,
                                      positionLastValue: item["p_last"] as? Int)
                        self.products[name] = order
                        
                        if let addOrderComp = addOrder, maxOrder < addOrderComp {
                            maxOrder = addOrderComp
                        }
                    }
                }
            } else {
               WebtrekkTracking.defaultLogger.logError("can't load project order information")
            }
            
            self.currentAddPosition = maxOrder + 1
        }
        
        func save(){
            var jsonObject = [[String:Any?]]()
            
            self.products.forEach() { (key, value) in
                let jsonItem : [String:Any?] = [
                "id" : key,
                "add_order" : value.addOrder,
                "p_first" : value.positionFirstValue,
                "p_last" : value.positionLastValue
                ]
                jsonObject.append(jsonItem)
            }
            
            if JSONSerialization.isValidJSONObject(jsonObject), let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []) {
                    self.userDefaults.set(key: DefaultsKeys.productListOrder, to: jsonData)
            } else {
                 WebtrekkTracking.defaultLogger.logError("can't save project order information")
            }
        }
        
        func savePositions(product: EcommerceProperties.Product){
            let position = product.position!
            let name = product.name!
            if let _ = self.products[name] {
                if let _ = self.products[name]?.positionFirstValue {
                    self.products[name]!.positionLastValue = position
                } else {
                    self.products[name]!.positionFirstValue = position
                }
            } else {
                self.products[name] = Order(positionFirstValue: position)
            }
        }
        
        func saveAddOrder(product: EcommerceProperties.Product){
            if let _ = self.products[product.name!] {
                self.products[product.name!]?.addOrder = currentAddPosition
            } else {
                self.products[product.name!] = Order(addOrder: currentAddPosition)
            }
            currentAddPosition = currentAddPosition + 1
        }
        
        
        func getFirstPosition(product: String?) -> Int? {
            if let product = product{
                return self.products[product]?.positionFirstValue
            } else{
                return nil
            }
        }
        
        func getLastPosition(product: String?) -> Int? {
            if let product = product{
                return self.products[product]?.positionLastValue ?? self.products[product]?.positionFirstValue
            } else{
                return nil
            }
        }
        
        func getAddOrder(product: String?) -> Int{
            if let product = product {
                return self.products[product]?.addOrder ?? Int.max
            } else{
                return Int.max
            }
        }
        
        func deleteAll(){
            self.userDefaults.remove(key: DefaultsKeys.productListOrder)
        }
        
        private var userDefaults : UserDefaults {
            return UserDefaults.standardDefaults.child(namespace: "webtrekk")
        }
        
    }
}
