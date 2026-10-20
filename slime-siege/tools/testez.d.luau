declare function describe(phrase: string, callback: () -> ()): ()
declare function describeSKIP(phrase: string, callback: () -> ()): ()
declare function it(phrase: string, callback: () -> ()): ()
declare function itSKIP(phrase: string, callback: () -> ()): ()
declare function beforeEach(callback: () -> ()): ()
declare function afterEach(callback: () -> ()): ()
declare function expect(value: any): any
