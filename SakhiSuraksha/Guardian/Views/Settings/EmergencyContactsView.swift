//
//  EmergencyContactsView.swift
//  Guardian
//

import SwiftUI
import SwiftData
import ContactsUI

struct EmergencyContactsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \EmergencyContact.name) private var contacts: [EmergencyContact]
    @State private var editing: EmergencyContact?
    @State private var showPicker = false
    @State private var showAdd = false

    var body: some View {
        List {
            if contacts.isEmpty {
                ContentUnavailableView("No contacts yet",
                                       systemImage: "person.2",
                                       description: Text("Add someone Guardian can alert in an emergency."))
            }
            ForEach(contacts) { contact in
                Button { editing = contact } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(GuardianTheme.accent.opacity(0.18))
                            Text(contact.initials).font(.subheadline.weight(.bold))
                                .foregroundStyle(GuardianTheme.accent)
                        }
                        .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(contact.name).font(.body.weight(.semibold))
                                if contact.isPrimary {
                                    Text("Primary").font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(GuardianTheme.safe.opacity(0.18))
                                        .foregroundStyle(GuardianTheme.safe)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(contact.phone).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Emergency Contacts")
        .toolbar {
            ToolbarItem(placement: .guardianTrailing) {
                Menu {
                    Button { showPicker = true } label: {
                        Label("Choose from Contacts", systemImage: "person.crop.circle")
                    }
                    Button { showAdd = true } label: {
                        Label("Add Manually", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add contact")
            }
        }
        .sheet(isPresented: $showPicker) {
            ContactPickerSheet { name, phone in
                let c = EmergencyContact(name: name, phone: phone, relationship: "",
                                         isPrimary: contacts.isEmpty, notifyOnJourney: true)
                context.insert(c)
                try? context.save()
            }
        }
        .sheet(isPresented: $showAdd) {
            ContactEditor(contact: nil)
        }
        .sheet(item: $editing) { contact in
            ContactEditor(contact: contact)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(contacts[index]) }
        try? context.save()
    }
}

// MARK: - CNContactPicker bridge

struct ContactPickerSheet: UIViewControllerRepresentable {
    let onPick: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String) -> Void
        init(onPick: @escaping (String, String) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            let contact = contactProperty.contact
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
            onPick(name, phone)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}

// MARK: - Manual editor

private struct ContactEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let contact: EmergencyContact?

    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var isPrimary = false
    @State private var notifyOnJourney = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone).phonePadKeyboard()
                    TextField("Relationship", text: $relationship)
                }
                Section {
                    Toggle("Primary contact", isOn: $isPrimary)
                    Toggle("Notify when I start a journey", isOn: $notifyOnJourney)
                }
            }
            .navigationTitle(contact == nil ? "Add Contact" : "Edit Contact")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || phone.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let contact {
                    name = contact.name; phone = contact.phone
                    relationship = contact.relationship
                    isPrimary = contact.isPrimary
                    notifyOnJourney = contact.notifyOnJourney
                }
            }
        }
    }

    private func save() {
        if let contact {
            contact.name = name; contact.phone = phone
            contact.relationship = relationship
            contact.isPrimary = isPrimary
            contact.notifyOnJourney = notifyOnJourney
        } else {
            context.insert(EmergencyContact(name: name, phone: phone,
                                            relationship: relationship,
                                            isPrimary: isPrimary,
                                            notifyOnJourney: notifyOnJourney))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
