//
//  main.swift
//  iSchemeInterpreter
//
//  Created by Yan Zhang on 1/15/15.
//  Copyright (c) 2015 Yan Zhang. All rights reserved.
//

import Foundation

func tokenize(source: String) -> [String] {
    let tokens = split(source.stringByReplacingOccurrencesOfString("(", withString: " ( ", options: NSStringCompareOptions.LiteralSearch).stringByReplacingOccurrencesOfString(")", withString: " ) ", options: NSStringCompareOptions.LiteralSearch), {$0.isMemberOf(NSCharacterSet.whitespaceAndNewlineCharacterSet())}, allowEmptySlices: false)
    return tokens
}

func readableLexes(lexes: [String]) -> String {
    return "[" + ", ".join(lexes.map(){"'" + $0 + "'"}) + "]"
}

class SExpression {
    var value: String?
    var children: [SExpression] = []
    var parent: SExpression?
    
    init(value: String?, parent: SExpression?) {
        self.value = value
        self.parent = parent
    }
    
    class func buildTree(source: String) -> SExpression {
        let root = SExpression(value: nil, parent: nil)
        var current = root
        for lex in tokenize(source) {
            switch lex {
            case "(":
                current.children.append(SExpression(value: "(", parent: current))
                current = current.children.last!
            case ")":
                current = current.parent!
            default:
                current.children.append(SExpression(value: lex, parent: current))
            }
        }
        return root
    }
    
    func evaluate(scope: SScope) -> SObject? {
        var current = self
        var scope = scope
        while (true) {
            if current.children.count == 0 {
                if let intValue = current.value?.toInt() {
                    return SNumber(intValue)
                } else {
                    return scope.find(current.value!)
                }
            } else if current.children.count == 1 {
                current = current.children[0]
            } else {
                let first = current.children[0]
                switch first.value! {
                case "if":
                    let condition = current.children[1].evaluate(scope) as SBool
                    current = (condition == SBool.True) ? current.children[2] : current.children[3]
                case "def":
                    return scope.define(current.children[1].value!, object: current.children[2].evaluate(SScope(parent: scope))!)
                case "begin":
                    var result: SObject? = nil
                    for stmt in self.children[1...self.children.count - 1]{
                        result = stmt.evaluate(scope)
                    }
                    return result
                case "func":
                    let body = current.children[2]
                    let para = map(current.children[1].children) {$0.value!}
                    let newScope = SScope(parent: scope)
                    return SFunction(body: body, para: para, scope: newScope)
                case "list":
                    if self.children.count == 1 {
                        return SList(values: [])
                    }
                    let objects = map(current.children[1...current.children.count - 1]) {$0.evaluate(scope)!}
                    return SList(values: objects)
                default:
                    if let builtinFunc = SScope.sharedBuiltinFunctions()[first.value!] {
                        let args = Array(current.children[1...current.children.count - 1])
                        return builtinFunc.run(args, scope: scope)
                    } else {
                        let function = (first.value == "(" ? first.evaluate(scope) : scope.find(first.value!)) as SFunction
                        let args = map(current.children[1...current.children.count - 1]) {$0.evaluate(scope)!}
                        let newFunc = function.update(args)
                        if newFunc.isPartial {
                            return newFunc.evaluate()
                        } else {
                            current = newFunc.body!
                            scope = newFunc.scope!
                        }
                    }
                }
            }
        }
    }
}

enum BuiltinFunction {
    case Add
    case Sub
    case Mul
    case Div
    case Mod
    case And
    case Or
    case Not
    case Eq
    case Lt
    case Bt
    case Lte
    case Bte
    case First
    case Rest
    case Append
    case Empty
    
    func run(args: [SExpression], scope: SScope) -> SObject {
        let evaluatedArgs = map(args) {$0.evaluate(scope)!}
        switch self {
        case .Add:
            var initialNum = SNumber(0)
            return reduce(evaluatedArgs, initialNum) {$0 + ($1 as SNumber)}
        case .Sub:
            var initialNum = evaluatedArgs[0] as SNumber
            if evaluatedArgs.count == 1 {
                return initialNum
            }
            return reduce(evaluatedArgs[1...evaluatedArgs.count - 1], initialNum) {$0 - ($1 as SNumber)}
        case .Mul:
            var initialNum = SNumber(1)
            return reduce(evaluatedArgs, initialNum) {$0 * ($1 as SNumber)}
        case .Div:
            var initialNum = evaluatedArgs[0] as SNumber
            if evaluatedArgs.count == 1 {
                return initialNum
            }
            return reduce(evaluatedArgs[1...evaluatedArgs.count - 1], initialNum) {$0 / ($1 as SNumber)}
        case .Mod:
            (evaluatedArgs.count == 2).orError("Mod has to have 2 args")
            return ((evaluatedArgs[0] as SNumber) % (evaluatedArgs[1] as SNumber))
        case .And:
            (evaluatedArgs.count > 0).orError("")
            for boolArg in evaluatedArgs {
                if (boolArg as SBool) == SBool.False {
                    return SBool.False
                }
            }
            return SBool.True
        case .Or:
            (evaluatedArgs.count > 0).orError("")
            for boolArg in evaluatedArgs {
                if (boolArg as SBool) == SBool.True {
                    return SBool.True
                }
            }
            return SBool.False
        case .Not:
            (evaluatedArgs.count == 1).orError("")
            if evaluatedArgs[0] as SBool == SBool.True {
                return SBool.False
            }
            return SBool.True
        case .Eq:
            return relationChain(map(evaluatedArgs, {$0 as SNumber})) {$0.value == $1.value}
        case .Lt:
            return relationChain(map(evaluatedArgs, {$0 as SNumber})) {$0.value < $1.value}
        case .Bt:
            return relationChain(map(evaluatedArgs, {$0 as SNumber})) {$0.value > $1.value}
        case .Lte:
            return relationChain(map(evaluatedArgs, {$0 as SNumber})) {$0.value <= $1.value}
        case .Bte:
            return relationChain(map(evaluatedArgs, {$0 as SNumber})) {$0.value >= $1.value}
        case .First:
            (evaluatedArgs.count == 1).orError("wrong args")
            if let l = evaluatedArgs[0] as? SList {
                return l.values[0]
            } else {
                fatalError("not a list type")
            }
        case .Rest:
            (evaluatedArgs.count == 1).orError("wrong args")
            if let l = evaluatedArgs[0] as? SList {
                if l.values.count <= 1 {
                    return SList(values: [])
                }
                return SList(values: Array(l.values[1...l.values.count - 1]))
            } else {
                fatalError("not a list type")
            }
        case .Append:
            (evaluatedArgs.count == 2).orError("wrong args")
            if let l1 = evaluatedArgs[0] as? SList {
                if let l2 = evaluatedArgs[1] as? SList {
                    return SList(values: l1.values + l2.values)
                } else {
                    fatalError("not a list type")
                }
            } else {
                fatalError("not a list type")
            }
        case .Empty:
            (evaluatedArgs.count == 1).orError("wrong args")
            if let l = evaluatedArgs[0] as? SList {
                return l.values.count == 0 ? SBool(true) : SBool(false)
            } else {
                fatalError("not a list type")
            }
        }
    }
}

func relationChain(numbers: [SNumber], relation: (SNumber, SNumber) -> Bool) -> SBool {
    (numbers.count > 1).orError("compares need at least 2 args")
    var cur = numbers[0]
    for number in numbers[1...numbers.count - 1] {
        if !relation(cur, number) {
            return SBool(false)
        }
        cur = number
    }
    return SBool(true)
}

class SScope {
    var parent: SScope?
    var variableTable: [String: SObject] = [String: SObject]()
    class func sharedBuiltinFunctions() -> [String: BuiltinFunction] {
        struct SharedInstance {
            static var builtinFunctions: [String: BuiltinFunction] =
            ["+": .Add,
            "-": .Sub,
            "*": .Mul,
            "/": .Div,
            "%": .Mod,
            "and": .And,
            "or": .Or,
            "not": .Not,
            "<": .Lt,
            "=": .Eq,
            ">": .Bt,
            "<=": .Lte,
            ">=": .Bte,
            "first": .First,
            "append": .Append,
            "rest": .Rest,
            "empty": .Empty]
        }
        return SharedInstance.builtinFunctions
    }
    
    init(parent: SScope?) {
        self.parent = parent
    }
    
    func REPL(evaluate: (String, SScope) -> SObject) {
        while true {
            print(">> ")
            if let newSource = input()?.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet()) {
                if newSource == ":quit" || newSource == ":q" {
                    exit(0)
                }
                println(evaluate(newSource, self).toString())
            }
        }
    }
    
    func find(name: String) -> SObject? {
        var current: SScope? = self
        while current != nil {
            if let v = current?.variableTable[name] {
                return v
            } else {
                current = current?.parent
            }
        }
        return nil
    }
    
    func define(name: String, object: SObject) -> SObject {
        variableTable[name] = object
        return object
    }
    
    func spawnScope(names: [String], values: [SObject]) -> SScope {
        (names.count >= values.count).orError("too many arguments")
        let newScope = SScope(parent: self)
        for var i = 0; i < values.count; i++ {
            newScope.variableTable[names[i]] = values[i]
        }
        return newScope
    }
    
    func findInTop(name: String) -> SObject? {
        return variableTable[name]
    }
}

protocol SObject {
    func toString() -> String
}

func + (op1: SNumber, op2: SNumber) -> SNumber {
    return SNumber(op1.value + op2.value)
}

func - (op1: SNumber, op2: SNumber) -> SNumber {
    return SNumber(op1.value - op2.value)
}

func * (op1: SNumber, op2: SNumber) -> SNumber {
    return SNumber(op1.value * op2.value)
}

func / (op1: SNumber, op2: SNumber) -> SNumber {
    return SNumber(op1.value / op2.value)
}

func % (op1: SNumber, op2: SNumber) -> SNumber {
    return SNumber(op1.value % op2.value)
}

struct SNumber: SObject {
    private var _value: Int
    var value: Int {
        return self._value
    }
    
    init(_ value: Int) {
        self._value = value
    }
    
    func toString() -> String {
        return String(_value)
    }
}

func ==(lhs: SBool, rhs: SBool) -> Bool {
    return lhs._value == rhs._value
}

struct SBool: SObject, Equatable {
    static let True = SBool(true)
    static let False = SBool(false)
    var _value: Bool
    init(_ v: Bool) {
        _value = v
    }
    static func value(v: Bool) -> SBool {
        return v ? True : False
    }
    
    func toString() -> String {
        return _value ? "True" : "False"
    }
}

extension Bool {
    func orError(errorMsg: String) {
        if self == false {
            fatalError(errorMsg)
        }
    }
}

struct SList: SObject, SequenceType {
    var values: [SObject]
    
    init(values: [SObject]) {
        self.values = [SObject]()
        for obj in values {
            self.values.append(obj as SObject)
        }
    }
    
    init(list: SList) {
        self.init(values: list.values)
    }
    
    func generate() -> IndexingGenerator<Array<SObject>> {
        return values.generate()
    }
    
    func toString() -> String {
        return "[" + join(", ", map(self.values, {$0.toString()})) + "]"
    }
}

struct SFunction: SObject {
    var body: SExpression?
    var parameters: [String] = []
    var scope: SScope?
    var isPartial: Bool {
        let cnt = self.computeFilledParameters().count
        return  cnt < self.parameters.count
    }
    
    init(body: SExpression, para: [String], scope: SScope) {
        self.body = body
        self.parameters = para
        self.scope = scope
    }
    
    func evaluate() -> SObject? {
        let filledPara = computeFilledParameters()
        if filledPara.count < parameters.count {
            return self
        } else {
            return body?.evaluate(self.scope!)
        }
    }
    
    func computeFilledParameters() -> [String] {
        return filter(parameters) {self.scope?.findInTop($0) != nil}
    }
    
    func update(args: [SObject]) -> SFunction {
        let existingArgs = map(filter(map(self.parameters) {self.scope?.findInTop($0)}) {$0 != nil}) {$0!}
        let newArgs = existingArgs + args
        let newScope = scope?.parent?.spawnScope(self.parameters, values: newArgs)
        return SFunction(body: self.body!, para: self.parameters, scope: newScope!)
    }
    
    func toString() -> String {
        let paras = join(" ", map(parameters) {
            para in
            if let obj = self.scope?.findInTop(para) {
                return para + ":" + obj.toString()
            } else {
                return para
            }
        })
        return String(format:"func (%@)\n", paras)
    }
}

func input() -> String? {
    var keyboard = NSFileHandle.fileHandleWithStandardInput()
    var inputData = keyboard.availableData
    return NSString(data: inputData, encoding:NSUTF8StringEncoding)
}

let scope = SScope(parent: nil)
scope.REPL {
    source, scope in
    return SExpression.buildTree(source).evaluate(scope)!
}
