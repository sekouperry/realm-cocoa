// @@Example: ex_cpp_dyn_query_between @@
#include <cassert>
#include <tightdb.hpp>

using namespace tightdb;

int main()
{
    // Create following table dynamically:

// @@Show@@
    // name    age
    // ------------
    // Alice    27
    // Bob      50
    // Peter    44

// @@EndShow@@
    Group group;
    TableRef table = group.get_table("test");
    table->add_column(type_String, "name");
    table->add_column(type_Int,    "age");

    table->add_empty_row();
    table->set_string(0, 0, "Alice");
    table->insert_int(1, 0, 27);

    table->add_empty_row();
    table->set_string(0, 1, "Bob");
    table->insert_int(1, 1, 50);

    table->add_empty_row();
    table->set_string(0, 2, "Peter");
    table->insert_int(1, 2, 44);

// @@Show@@
    // Find rows where age >= 20 && age <= 48 (age is column 1)
    Query query = table->where().between(1, 20, 48);
    TableView view = query.find_all();

    assert(view.size() == 2);
    assert(view.get_string(0,0) == "Alice");
    assert(view.get_string(0,1) == "Peter");
// @@EndShow@@
}
// @@EndExample@@