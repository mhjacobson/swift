// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -parse -verify %s

// REQUIRES: objc_interop

import blocks
import Foundation

var someNSString : NSString
func useString(_ s: String) {}

accepts_block { }
someNSString.enumerateLines {(s:String?) in }
someNSString.enumerateLines {s in }
someNSString.enumerateLines({ useString($0) })

accepts_block(/*not a block=*/()) // expected-error{{cannot convert value of type '()' to expected argument type 'my_block_t' (aka '() -> ()'}}

func testNoEscape(f: @noescape @convention(block) () -> Void, nsStr: NSString,
                  fStr: @noescape (String!) -> Void) {
  accepts_noescape_block(f)
  accepts_noescape_block(f)

  // rdar://problem/19818617
  nsStr.enumerateLines(fStr) // okay due to @noescape

  _ = nsStr.enumerateLines as Int // expected-error{{cannot convert value of type '(@noescape (String) -> Void) -> Void' to type 'Int' in coercion}}
}

func checkTypeImpl<T>(_ a: inout T, _: T.Type) {}
do {
  var blockOpt = blockWithoutNullability()
  checkTypeImpl(&blockOpt, Optional<my_block_t>.self)
  var block: my_block_t = blockWithoutNullability()
}
do {
  var block = blockWithNonnull()
  checkTypeImpl(&block, my_block_t.self)
}
do {
  var blockOpt = blockWithNullUnspecified()
  checkTypeImpl(&blockOpt, Optional<my_block_t>.self)
  var block: my_block_t = blockWithNullUnspecified()
}
do {
  var block = blockWithNullable()
  checkTypeImpl(&block, Optional<my_block_t>.self)
}
