
Attribute::Attribute(string name, int prob)
	:  attribute(name), attribute_probability(prob)
{
}

void
Attribute::OutputAttribute(std::ostream &out, string option)
{
	out << " __attribute__((" << attribute << option << "))";
}

BooleanAttribute::BooleanAttribute(string name, int prob)
	: Attribute(name, prob)
{
}

void
BooleanAttribute::OutputAttributes(std::ostream &out)
{
	if(rnd_flipcoin(attribute_probability))
		OutputAttribute(out, "");
}

MultiValuedAttribute::MultiValuedAttribute(string name, int prob, vector<string> arguments)
	: Attribute(name, prob), attribute_values(arguments)
{
}

void
MultiValuedAttribute::OutputAttributes(std::ostream &out)
{
	if(rnd_flipcoin(attribute_probability))
		OutputAttribute(out, "(\"" + attribute_values[rnd_upto(attribute_values.size())] + "\")");
}

AlignedAttribute::AlignedAttribute(string name, int prob)
	: Attribute(name, prob)
{
}

void
AlignedAttribute::OutputAttributes(std::ostream &out)
{
	if(rnd_flipcoin(attribute_probability)){
		int power = rnd_upto(16);
		OutputAttribute(out, "(" + to_string(1 << power) + ")");
	}
}

SectionAttribute::SectionAttribute(string name, int prob)
	: Attribute(name, prob)
{
}

void
SectionAttribute::OutputAttributes(std::ostream &out)
{
	if(rnd_flipcoin(attribute_probability)){
		OutputAttribute(out, "(\"usersection" + to_string(rnd_upto(10)) + "\")");
	}
}

