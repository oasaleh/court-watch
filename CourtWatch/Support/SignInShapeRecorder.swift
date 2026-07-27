//
//  SignInShapeRecorder.swift
//  CourtWatch
//
//  Records the *shape* of a sign-in reply, and none of its contents.
//
//  The user's one real sign-in is the only observation of a success response
//  this project will ever get, and it answers four things currently written
//  down as unknown: whether `public_customer_id` is populated, whether the
//  tokens arrive, what else the body carries, and therefore whether the extra
//  call somebody would otherwise have built is needed at all.
//
//  **Key names and value types only. Never a value.** Not the message, not
//  `access_token`, not `sign_in_token_id`, and obviously not the credential.
//  Key names and types answer every one of those questions; values answer none
//  of them and every one of them is a liability.
//
//  Capturing the raw body to a fixture was rejected outright: it would put a
//  live session token in a file on disk and would be the single most likely way
//  this project ever committed a secret.
//
//  Value-blindness is enforced by a test that feeds this recognisable markers
//  and requires none of them to appear in the output — not by care.
//
//  `#if DEBUG` in full, like the failure harness, so the Release gate that
//  already exists covers this too.
//

#if DEBUG

    import Foundation

    nonisolated enum SignInShapeRecorder {

        /// Written where a person can read it without a debugger.
        static let fileName = "signin-response-shape.txt"

        /// A description of the reply's structure, with every value replaced by
        /// the name of its type.
        static func shape(of data: Data) -> String {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
                return "the reply was not JSON (\(data.count) bytes)"
            }

            return describe(parsed, indent: 0)
        }

        /// Appends the shape to the app's Documents directory.
        ///
        /// Appends rather than replaces so a second sign-in does not erase the
        /// first, and stamped with nothing but a counter — a timestamp here
        /// would be the app's only date handling outside its one date file.
        static func record(_ data: Data, producedIdentity: Bool) {
            let report = """
                --- sign-in reply shape ---
                a usable customer id was produced: \(producedIdentity)
                \(shape(of: data))

                """

            guard
                let directory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
            else { return }

            let destination = directory.appendingPathComponent(fileName)

            if let existing = try? String(contentsOf: destination, encoding: .utf8) {
                try? (existing + report).write(to: destination, atomically: true, encoding: .utf8)
            } else {
                try? report.write(to: destination, atomically: true, encoding: .utf8)
            }
        }

        /// Walks the structure naming keys and types.
        ///
        /// Every leaf renders as the *name of its type*. A string renders as
        /// `string`, a number as `number` — never `"0000"`, never `4471056`.
        /// A leaf that rendered its value would be the whole failure of this
        /// file, so there is exactly one place a leaf is turned into text and
        /// it does not have the value in scope.
        private static func describe(_ value: Any, indent: Int) -> String {
            let padding = String(repeating: "  ", count: indent)

            if let object = value as? [String: Any] {
                guard object.isEmpty == false else { return "\(padding)(empty object)" }

                // Sorted so two recordings of the same shape read identically.
                return object.keys.sorted()
                    .map { key in
                        let child = object[key]!

                        if child is [String: Any] || child is [Any] {
                            return "\(padding)\(key): \(typeName(of: child))\n"
                                + describe(child, indent: indent + 1)
                        }

                        return "\(padding)\(key): \(typeName(of: child))"
                    }
                    .joined(separator: "\n")
            }

            if let array = value as? [Any] {
                guard let first = array.first else { return "\(padding)(empty array)" }

                return "\(padding)[\(array.count) x \(typeName(of: first))]"
            }

            return "\(padding)\(typeName(of: value))"
        }

        /// The name of a JSON type, derived from the value's class alone. The
        /// value itself is never interpolated.
        static func typeName(of value: Any?) -> String {
            guard let value, value is NSNull == false else { return "null" }

            if value is [String: Any] { return "object" }
            if value is [Any] { return "array" }

            if let number = value as? NSNumber {
                // `Bool` and `Int` are both `NSNumber` once JSONSerialization
                // has been through them; the object type is what tells them
                // apart, and neither reveals the value.
                return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
            }

            if value is String { return "string" }

            return "unknown"
        }
    }

#endif
