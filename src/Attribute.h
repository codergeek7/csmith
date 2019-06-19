
class Attribute
{
public:
	string attribute;
	int attribute_probability;
	Attribute(string, int);
	void OutputAttribute(std::ostream &, string);
	virtual void OutputAttributes(std::ostream &) = 0;
};

class BooleanAttribute : public Attribute
{
public:
	BooleanAttribute(string, int);
	void OutputAttributes(std::ostream &);
};

class MultiValuedAttribute : public Attribute
{
public:
	vector<string> attribute_values;
	MultiValuedAttribute(string, int, vector<string>);
	void OutputAttributes(std::ostream &);
};

class AlignedAttribute : public Attribute
{
public:
	AlignedAttribute(string, int);
	void OutputAttributes(std::ostream &);
};

class SectionAttribute : public Attribute
{
public:
	SectionAttribute(string, int);
	void OutputAttributes(std::ostream &);
};
